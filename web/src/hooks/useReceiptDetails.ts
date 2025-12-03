import { useSuiClientQueries } from "@mysten/dapp-kit";
import { bcs } from "@mysten/sui/bcs";
import { Transaction } from "@mysten/sui/transactions";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const { errorLog } = loggers("app:hooks:useReceiptDetails");

export interface ReceiptDetails {
  receiptId: string;
  vaultId: string;
  status: number; // 0: normal, 1: pending_deposit, 2: pending_withdraw, 3: pending_withdraw_with_auto_transfer
  shares: string;
  pending_deposit_balance: string;
  pending_withdraw_shares: string;
  claimable_principal: string;
  last_deposit_time: number;
  reward_indices: string; // Table stored as object ID
  unclaimed_rewards: string; // Table stored as object ID
}

/**
 * Hook to query receipt details directly using vault_receipt_info view function
 * More efficient than querying dynamic fields
 * Internally uses useReceiptsDetails for code reuse
 *
 * @param vaultId - The vault object ID
 * @param receiptId - The receipt object ID (address)
 * @param coinType - The coin type for the vault
 */
export function useReceiptDetails(
  vaultId: string | null,
  receiptId: string | null,
  coinType: string | null,
) {
  // Use batch query with single receipt ID
  const { detailsMap, isLoading, error, refetch } = useReceiptsDetails(
    vaultId,
    receiptId ? [receiptId] : [],
    coinType,
  );

  // Extract single receipt details from map
  const details = useMemo(() => {
    if (!receiptId) {
      return null;
    }

    return detailsMap.get(receiptId) ?? null;
  }, [detailsMap, receiptId]);

  return {
    details,
    isLoading,
    error,
    refetch,
  };
}

/**
 * Hook to query receipt details for multiple receipts using useSuiClientQueries
 * Returns a map of receipt ID to details for efficient lookup
 *
 * @param vaultId - The vault object ID
 * @param receiptIds - Array of receipt object IDs
 * @param coinType - The coin type for the vault
 */
export function useReceiptsDetails(
  vaultId: string | null,
  receiptIds: string[],
  coinType: string | null,
) {
  // Build transaction objects for each receipt
  const transactions = useMemo(() => {
    if (!vaultId || !coinType || receiptIds.length === 0) {
      return [];
    }

    return receiptIds.map((receiptId) => {
      const tx = new Transaction();

      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID}::vault::vault_receipt_info`,
        typeArguments: [coinType],
        arguments: [tx.object(vaultId), tx.pure.address(receiptId)],
      });

      return tx;
    });
  }, [vaultId, receiptIds, coinType]);

  // Batch query all receipt details
  // Use stable queryKey based on vaultId and receiptId to avoid duplicate queries
  const results = useSuiClientQueries({
    queries: transactions.map((tx, index) => {
      const receiptId = receiptIds[index];

      return {
        method: "devInspectTransactionBlock" as const,
        params: {
          sender:
            "0x0000000000000000000000000000000000000000000000000000000000000000",
          transactionBlock: tx,
        },
        options: {
          // Use stable queryKey based on vaultId and receiptId instead of Transaction object
          // This prevents duplicate queries when Transaction objects are recreated on re-render
          queryKey: ["vault_receipt_info", vaultId, receiptId, coinType],
          enabled:
            !!vaultId && !!receiptId && !!VOLO_VAULT_PACKAGE_ID && !!coinType,
          refetchInterval: 10000,
          staleTime: 5000,
        },
      };
    }),
  });

  // Parse results and create a map
  const detailsMap = useMemo(() => {
    const map = new Map<
      string,
      {
        status: number;
        shares: string;
        pending_deposit_balance: string;
        pending_withdraw_shares: string;
        last_deposit_time: number;
        claimable_principal: string;
        reward_indices: string;
        unclaimed_rewards: string;
        receiptId: string;
        vaultId: string;
      }
    >();

    results.forEach((result, index) => {
      const receiptId = receiptIds[index];

      if (!receiptId || !result.data) {
        return;
      }

      const data = result.data;

      if (
        !data.results ||
        data.results.length === 0 ||
        !data.results[0]?.returnValues ||
        data.results[0].returnValues.length === 0
      ) {
        return;
      }

      const returnValue = data.results[0].returnValues[0];

      if (!returnValue || !Array.isArray(returnValue[0])) {
        return;
      }

      // Parse VaultReceiptInfo struct using BCS
      const valueBytes = new Uint8Array(returnValue[0] as number[]);

      const VaultReceiptInfo = bcs.struct("VaultReceiptInfo", {
        status: bcs.u8(),
        shares: bcs.u256(),
        pending_deposit_balance: bcs.u64(),
        pending_withdraw_shares: bcs.u256(),
        last_deposit_time: bcs.u64(),
        claimable_principal: bcs.u64(),
        reward_indices: bcs.Address,
        unclaimed_rewards: bcs.Address,
      });

      try {
        const parsed = VaultReceiptInfo.parse(valueBytes);

        map.set(receiptId, {
          ...parsed,
          last_deposit_time: Number(parsed.last_deposit_time),
          receiptId,
          vaultId: vaultId!,
        });
      } catch (parseError) {
        errorLog(
          "Failed to parse VaultReceiptInfo with BCS for receipt %s: %O",
          receiptId,
          parseError,
        );
      }
    });

    return map;
  }, [results, receiptIds, vaultId]);

  const isLoading = results.some((result) => result.isLoading);
  const error = results.find((result) => result.error)?.error;

  return {
    detailsMap,
    isLoading,
    error,
    refetch: () => {
      results.forEach((result) => {
        result.refetch();
      });
    },
  };
}
