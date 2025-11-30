import { useSuiClientQuery, useSuiClient } from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { useQuery } from "@tanstack/react-query";

import { loggers } from "@/utils/debug";

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";
const { errorLog } = loggers("app:hooks:useVaultInfo");

/**
 * Hook to query vault information including deposit_fee_rate and share_ratio
 *
 * Uses get_share_ratio_without_update via devInspectTransactionBlock for real-time share ratio.
 * Share ratio is only used for display purposes, not for deposit calculations.
 *
 * @param vaultId - The vault object ID
 */
export function useVaultInfo(vaultId: string | null) {
  const client = useSuiClient();

  // Query vault object to get deposit_fee_rate and extract coin type from type
  const {
    data: vaultData,
    isLoading: isLoadingVault,
    error: vaultError,
    refetch: refetchVault,
  } = useSuiClientQuery(
    "getObject",
    {
      id: vaultId || "",
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled: !!vaultId,
      refetchInterval: 30000, // Refetch every 30 seconds
    },
  );

  // Extract fields from vault object
  let depositFeeRate: number | null = null;
  let totalShares: bigint | null = null;
  let freePrincipal: bigint | null = null;
  let claimablePrincipal: bigint | null = null;
  let withdrawFeeRate: number | null = null;
  let lockingTimeForWithdraw: number | null = null;
  let lockingTimeForCancelRequest: number | null = null;
  let assetTypes: string[] = [];
  let coinType: string | null = null;

  if (vaultData?.data) {
    if ("content" in vaultData.data) {
      const content = vaultData.data.content;

      if (
        content &&
        "dataType" in content &&
        content.dataType === "moveObject" &&
        "fields" in content
      ) {
        const fields = content.fields as Record<string, unknown>;
        const feeRate = fields.deposit_fee_rate as string | number | undefined;
        const shares = fields.total_shares as string | number | undefined;
        const withdrawFee = fields.withdraw_fee_rate as
          | string
          | number
          | undefined;
        const lockingWithdraw = fields.locking_time_for_withdraw as
          | string
          | number
          | undefined;
        const lockingCancel = fields.locking_time_for_cancel_request as
          | string
          | number
          | undefined;
        const assetTypesVec = fields.asset_types as string[] | undefined;

        // Extract Balance values (Balance<T> has a 'value' field)
        const freePrincipalBalance = fields.free_principal as
          | { value?: string | number }
          | string
          | number
          | undefined;
        const claimablePrincipalBalance = fields.claimable_principal as
          | { value?: string | number }
          | string
          | number
          | undefined;

        if (feeRate !== undefined) {
          depositFeeRate = Number(feeRate);
        }
        if (shares !== undefined) {
          totalShares = BigInt(String(shares));
        }
        if (withdrawFee !== undefined) {
          withdrawFeeRate = Number(withdrawFee);
        }
        if (lockingWithdraw !== undefined) {
          lockingTimeForWithdraw = Number(lockingWithdraw);
        }
        if (lockingCancel !== undefined) {
          lockingTimeForCancelRequest = Number(lockingCancel);
        }
        if (assetTypesVec !== undefined && Array.isArray(assetTypesVec)) {
          assetTypes = assetTypesVec;
        }

        // Extract coin type from vault type
        if (vaultData.data.type) {
          const typeStr = String(vaultData.data.type);
          // Type format: 0x...::vault::Vault<0x...::coin_type::COIN_TYPE>
          const match = typeStr.match(/<([^>]+)>/);

          if (match && match[1]) {
            coinType = match[1];
          }
        }

        // Extract Balance value
        if (freePrincipalBalance !== undefined) {
          if (
            typeof freePrincipalBalance === "object" &&
            freePrincipalBalance !== null
          ) {
            const value = freePrincipalBalance.value;

            if (value !== undefined) {
              freePrincipal = BigInt(String(value));
            }
          } else if (
            typeof freePrincipalBalance === "string" ||
            typeof freePrincipalBalance === "number"
          ) {
            freePrincipal = BigInt(String(freePrincipalBalance));
          }
        }

        if (claimablePrincipalBalance !== undefined) {
          if (
            typeof claimablePrincipalBalance === "object" &&
            claimablePrincipalBalance !== null
          ) {
            const value = claimablePrincipalBalance.value;

            if (value !== undefined) {
              claimablePrincipal = BigInt(String(value));
            }
          } else if (
            typeof claimablePrincipalBalance === "string" ||
            typeof claimablePrincipalBalance === "number"
          ) {
            claimablePrincipal = BigInt(String(claimablePrincipalBalance));
          }
        }
      }
    }
  }

  // Query share_ratio using get_share_ratio_without_update via devInspectTransactionBlock
  const {
    data: shareRatio,
    isLoading: isLoadingShareRatio,
    refetch: refetchShareRatio,
  } = useQuery({
    queryKey: ["vault-share-ratio", vaultId, coinType],
    queryFn: async () => {
      if (!vaultId || !VOLO_VAULT_PACKAGE_ID || !coinType) {
        return null;
      }

      try {
        const tx = new Transaction();

        tx.moveCall({
          target: `${VOLO_VAULT_PACKAGE_ID}::vault::get_share_ratio_without_update`,
          typeArguments: [coinType],
          arguments: [tx.object(vaultId)],
        });

        const result = await client.devInspectTransactionBlock({
          sender:
            "0x0000000000000000000000000000000000000000000000000000000000000000",
          transactionBlock: tx,
        });

        if (
          result.results &&
          result.results.length > 0 &&
          result.results[0]?.returnValues &&
          result.results[0].returnValues.length > 0
        ) {
          const returnValue = result.results[0].returnValues[0];

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
        errorLog("Failed to get share ratio: %O", error);
      }

      // Return null on error, let caller handle the error state
      return null;
    },
    enabled: !!vaultId && !!VOLO_VAULT_PACKAGE_ID && !!coinType,
    refetchInterval: 30000, // Refetch every 30 seconds
    staleTime: 15000, // Consider stale after 15 seconds
  });

  return {
    depositFeeRate,
    totalShares,
    shareRatio: shareRatio ?? null,
    freePrincipal,
    claimablePrincipal,
    withdrawFeeRate,
    lockingTimeForWithdraw,
    lockingTimeForCancelRequest,
    assetTypes,
    isLoading: isLoadingVault || isLoadingShareRatio,
    error: vaultError,
    refetch: () => {
      refetchVault();
      refetchShareRatio();
    },
  };
}
