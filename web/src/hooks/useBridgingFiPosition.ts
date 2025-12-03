import { useMemo, useState, useEffect } from "react";
import { useSuiClientQuery } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";

import { loggers } from "@/utils/debug";
import {
  formatAPR,
  formatDayIndex,
  calculateCurrentDebt,
  getCurrentDayIndex,
} from "@/utils/bridgingfi";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const { debugLog, errorLog } = loggers("app:hooks:useBridgingFiPosition");

export interface BridgingFiPositionData {
  objectId: string;
  vaultId: string;
  custodianAccount: string;
  outstandingBalance: bigint;
  aprDecimal: bigint;
  lastUpdateDay: number;
  coinType: string; // Coin type from vault (for decimals lookup)
  // Computed fields
  aprPercentage: string;
  lastUpdateDate: string;
  currentDebt: bigint; // Approximate, calculated client-side
  currentDebtCalculatedAt?: Date; // When current debt was calculated
}

/**
 * Hook to fetch BridgingFiPosition from vault
 *
 * @param vaultId - The vault object ID
 * @param coinType - The principal coin type (for type arguments)
 * @param assetType - The asset type string (e.g., "0x...::bridgingfi_adapter::BridgingFiPosition0")
 */
export function useBridgingFiPosition(
  vaultId: string | null,
  coinType: string | null,
  assetType: string | null,
) {
  // Step 1: Get vault object to extract assets Bag ID
  const {
    data: vaultData,
    isLoading: isLoadingVault,
    error: vaultError,
  } = useSuiClientQuery(
    "getObject",
    {
      id: vaultId || "",
      options: {
        showContent: true,
      },
    },
    {
      enabled: !!vaultId,
    },
  );

  // Extract assets Bag ID from vault
  const assetsBagId = useMemo(() => {
    if (!vaultData?.data || !("content" in vaultData.data)) {
      return null;
    }

    const content = vaultData.data.content;

    if (
      !content ||
      content.dataType !== "moveObject" ||
      !("fields" in content)
    ) {
      return null;
    }

    const fields = content.fields as Record<string, unknown>;
    const assets = fields.assets;

    // Bag structure: { type: "...", fields: { id: { id: "..." }, size: "..." } }
    if (assets && typeof assets === "object" && "fields" in assets) {
      const assetsFields = (assets as { fields?: { id?: { id?: string } } })
        .fields;

      if (assetsFields?.id?.id) {
        return assetsFields.id.id;
      }
    }

    return null;
  }, [vaultData]);

  // Step 3: Query dynamic object field from assets Bag using asset_type as key
  // Bag<String, BridgingFiPosition> stores BridgingFiPosition as dynamic object fields
  // since BridgingFiPosition has 'key' ability
  // Based on actual storage format: name='ec71942d8c4cfdc2b509de5c727853cf923ce4fcf6e50098c7dc7753e4c4160e::bridgingfi_adapter::BridgingFiPosition0'
  // The key is stored as AsciiString (0x1::ascii::String) without 0x prefix
  const {
    data: dynamicFieldData,
    isLoading: isLoadingDynamicField,
    error: dynamicFieldError,
  } = useSuiClientQuery(
    "getDynamicFieldObject",
    {
      parentId: assetsBagId || "",
      name: {
        type: "0x1::ascii::String", // Use AsciiString, not String
        value: assetType,
      },
    },
    {
      enabled: !!assetsBagId && !!assetType,
    },
  );

  // Step 4: Extract BridgingFiPosition object ID and data from dynamic field
  // getDynamicFieldObject returns: { content: { fields: { value: { fields: {...} } } } }
  // The value field contains the actual BridgingFiPosition object data
  const { positionObjectId, positionData } = useMemo(() => {
    if (!dynamicFieldData?.data) {
      return { positionObjectId: null, positionData: null };
    }

    // Extract object ID from dynamic field
    const objectId = dynamicFieldData.data.objectId || null;

    // Extract BridgingFiPosition data from content.fields.value
    // Structure: content.fields.value.fields contains the actual position fields
    let data = null;

    if (
      dynamicFieldData.data &&
      "content" in dynamicFieldData.data &&
      dynamicFieldData.data.content &&
      dynamicFieldData.data.content.dataType === "moveObject" &&
      "fields" in dynamicFieldData.data.content
    ) {
      const fields = dynamicFieldData.data.content.fields as Record<
        string,
        unknown
      >;
      const value = fields.value as
        | {
            type?: string;
            fields?: Record<string, unknown>;
          }
        | undefined;

      if (value && value.fields) {
        // The value.fields contains the actual BridgingFiPosition data
        data = {
          content: {
            dataType: "moveObject" as const,
            fields: value.fields,
          },
        };
      }
    }

    return { positionObjectId: objectId, positionData: data };
  }, [dynamicFieldData]);

  // Step 5: Parse position data
  const position = useMemo((): BridgingFiPositionData | null => {
    if (!positionData || !("content" in positionData)) {
      return null;
    }

    const content = positionData.content;

    if (
      !content ||
      content.dataType !== "moveObject" ||
      !("fields" in content)
    ) {
      return null;
    }

    const fields = content.fields as Record<string, unknown>;

    const vaultIdField = fields.vault_id as string | undefined;
    const custodianAccountField = fields.custodian_account as
      | string
      | undefined;
    const outstandingBalanceField = fields.outstanding_balance as
      | string
      | number
      | undefined;
    const aprDecimalField = fields.apr_decimal as string | number | undefined;
    const lastUpdateDayField = fields.last_update_day as
      | string
      | number
      | undefined;

    if (
      !vaultIdField ||
      !custodianAccountField ||
      outstandingBalanceField === undefined ||
      aprDecimalField === undefined ||
      lastUpdateDayField === undefined
    ) {
      debugLog("Missing required fields in BridgingFiPosition");

      return null;
    }

    const outstandingBalance = BigInt(String(outstandingBalanceField));
    const aprDecimal = BigInt(String(aprDecimalField));
    const lastUpdateDay = Number(lastUpdateDayField);
    const currentDay = getCurrentDayIndex();

    return {
      objectId: positionObjectId || "",
      vaultId: vaultIdField,
      custodianAccount: custodianAccountField,
      outstandingBalance,
      aprDecimal,
      lastUpdateDay,
      coinType: coinType || "", // Store coinType from hook parameter
      aprPercentage: formatAPR(aprDecimal),
      lastUpdateDate: formatDayIndex(lastUpdateDay),
      currentDebt: calculateCurrentDebt(
        outstandingBalance,
        aprDecimal,
        lastUpdateDay,
        currentDay,
      ),
    };
  }, [positionData, positionObjectId, coinType]);

  // Step 6: Fetch accurate current debt from on-chain view function
  // Build transaction for devInspectTransactionBlock
  const debtTransaction = useMemo(() => {
    if (!positionObjectId || !VOLO_VAULT_PACKAGE_ID_LATEST) {
      return null;
    }

    const tx = new Transaction();

    // Call get_current_debt view function
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::get_current_debt`,
      typeArguments: [],
      arguments: [tx.object(positionObjectId), tx.object(SUI_CLOCK_OBJECT_ID)],
    });

    return tx;
  }, [positionObjectId]);

  const { data: onChainCurrentDebtResult, isLoading: isLoadingOnChainDebt } =
    useSuiClientQuery(
      "devInspectTransactionBlock",
      {
        sender:
          "0x0000000000000000000000000000000000000000000000000000000000000000",
        transactionBlock: debtTransaction || new Transaction(),
      },
      {
        enabled:
          !!vaultId &&
          !!coinType &&
          !!positionObjectId &&
          !!debtTransaction &&
          !!VOLO_VAULT_PACKAGE_ID_LATEST,
        refetchInterval: 30000, // Refetch every 30 seconds
        staleTime: 15000, // Consider stale after 15 seconds
      },
    );

  // Track when current debt was calculated
  const [currentDebtCalculatedAt, setCurrentDebtCalculatedAt] =
    useState<Date | null>(null);

  // Parse on-chain current debt from result
  const onChainCurrentDebt = useMemo(() => {
    if (!onChainCurrentDebtResult) {
      return null;
    }

    try {
      if (
        onChainCurrentDebtResult.results &&
        onChainCurrentDebtResult.results.length > 0 &&
        onChainCurrentDebtResult.results[0]?.returnValues &&
        onChainCurrentDebtResult.results[0].returnValues.length > 0
      ) {
        const returnValue = onChainCurrentDebtResult.results[0].returnValues[0];

        if (returnValue && Array.isArray(returnValue[0])) {
          const valueBytes = returnValue[0];

          // Convert bytes array to BigInt (u256)
          let value = 0n;

          for (let i = valueBytes.length - 1; i >= 0; i--) {
            value = value * 256n + BigInt(valueBytes[i] || 0);
          }

          return value;
        }
      }
    } catch (error) {
      errorLog("Failed to parse current debt from chain: %O", error);
    }

    return null;
  }, [onChainCurrentDebtResult]);

  // Update calculation timestamp when debt value changes (both on-chain and client-side)
  useEffect(() => {
    if (onChainCurrentDebt !== null && onChainCurrentDebt !== undefined) {
      setCurrentDebtCalculatedAt(new Date());
    }
  }, [onChainCurrentDebt]);

  // Also update timestamp when position data changes (for client-side calculation)
  useEffect(() => {
    if (position) {
      setCurrentDebtCalculatedAt(new Date());
    }
  }, [position?.currentDebt]);

  // Use on-chain debt if available, otherwise use client-side calculation
  const finalPosition = useMemo((): BridgingFiPositionData | null => {
    if (!position) {
      return null;
    }

    const isUsingOnChainDebt =
      onChainCurrentDebt !== null && onChainCurrentDebt !== undefined;

    return {
      ...position,
      currentDebt: isUsingOnChainDebt
        ? onChainCurrentDebt
        : position.currentDebt,
      currentDebtCalculatedAt: currentDebtCalculatedAt || undefined,
      coinType: coinType || position.coinType, // Preserve coinType
    };
  }, [position, onChainCurrentDebt, currentDebtCalculatedAt, coinType]);

  const isLoading =
    isLoadingVault || isLoadingDynamicField || isLoadingOnChainDebt;

  const error = vaultError || dynamicFieldError;

  return {
    position: finalPosition,
    isLoading,
    error,
    assetType,
  };
}
