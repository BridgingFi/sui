import { useSuiClientQuery } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { useMemo } from "react";

import { bytesToBigInt } from "@/utils/format";
import { loggers } from "@/utils/debug";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const { errorLog } = loggers("app:hooks:useVaultShareRatio");

/**
 * Hook to query vault share ratio using get_share_ratio_without_update
 * Share ratio is only used for display purposes, not for deposit calculations.
 *
 * @param vaultId - The vault object ID
 * @param coinType - The coin type for the vault (extracted from vault type)
 */
export function useVaultShareRatio(
  vaultId: string | null,
  coinType: string | null,
) {
  // Build transaction for devInspectTransactionBlock
  const shareRatioTransaction = useMemo(() => {
    if (!vaultId || !VOLO_VAULT_PACKAGE_ID || !coinType) {
      return null;
    }

    const tx = new Transaction();

    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID}::vault::get_share_ratio_without_update`,
      typeArguments: [coinType],
      arguments: [tx.object(vaultId)],
    });

    return tx;
  }, [vaultId, coinType]);

  // Query share_ratio using get_share_ratio_without_update via devInspectTransactionBlock
  const {
    data: shareRatioResult,
    isLoading,
    error,
    refetch,
  } = useSuiClientQuery(
    "devInspectTransactionBlock",
    {
      sender:
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      transactionBlock: shareRatioTransaction || new Transaction(),
    },
    {
      enabled:
        !!vaultId &&
        !!VOLO_VAULT_PACKAGE_ID &&
        !!coinType &&
        !!shareRatioTransaction,
      refetchInterval: 30000, // Refetch every 30 seconds
      staleTime: 15000, // Consider stale after 15 seconds
    },
  );

  // Parse share ratio from result
  const shareRatio = useMemo(() => {
    if (!shareRatioResult) {
      return null;
    }

    try {
      if (
        shareRatioResult.results &&
        shareRatioResult.results.length > 0 &&
        shareRatioResult.results[0]?.returnValues &&
        shareRatioResult.results[0].returnValues.length > 0
      ) {
        const returnValue = shareRatioResult.results[0].returnValues[0];

        if (returnValue && Array.isArray(returnValue[0])) {
          // Convert bytes array directly to bigint (little-endian)
          return bytesToBigInt(returnValue[0]);
        }
      }
    } catch (error) {
      errorLog("Failed to parse share ratio: %O", error);
    }

    return null;
  }, [shareRatioResult]);

  return {
    shareRatio,
    isLoading,
    error,
    refetch,
  };
}
