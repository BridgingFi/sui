import { useSuiClientQuery, useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";

/**
 * Hook to query vault information including deposit_fee_rate and share_ratio
 *
 * Only uses events to query share_ratio (no devInspectTransactionBlock).
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

  // Query share_ratio from events only (for display purposes)
  const {
    data: shareRatio,
    isLoading: isLoadingShareRatio,
    refetch: refetchShareRatio,
  } = useQuery({
    queryKey: ["vault-share-ratio-events", vaultId],
    queryFn: async () => {
      if (!vaultId || !VOLO_VAULT_PACKAGE_ID) {
        return null;
      }

      try {
        const eventType = `${VOLO_VAULT_PACKAGE_ID}::vault::ShareRatioUpdated`;

        const events = await client.queryEvents({
          query: {
            MoveEventType: eventType,
          },
          limit: 1, // Get only the latest event
          order: "descending",
        });

        if (events.data && events.data.length > 0) {
          // Find the latest event for this vault
          for (const event of events.data) {
            if (
              event.parsedJson &&
              typeof event.parsedJson === "object" &&
              "vault_id" in event.parsedJson
            ) {
              const eventVaultId = String(event.parsedJson.vault_id);
              const parsedJson = event.parsedJson as Record<string, unknown>;

              if (eventVaultId === vaultId) {
                const shareRatioValue = parsedJson.share_ratio;

                if (shareRatioValue !== undefined) {
                  // Convert to BigInt
                  if (typeof shareRatioValue === "string") {
                    return BigInt(shareRatioValue);
                  }

                  if (typeof shareRatioValue === "number") {
                    return BigInt(shareRatioValue);
                  }

                  if (Array.isArray(shareRatioValue)) {
                    let value = 0n;

                    for (let i = shareRatioValue.length - 1; i >= 0; i--) {
                      value = value * 256n + BigInt(shareRatioValue[i] || 0);
                    }

                    return value;
                  }
                }
              }
            }
          }
        }

        return null;
      } catch {
        return null;
      }
    },
    enabled: !!vaultId && !!VOLO_VAULT_PACKAGE_ID,
    refetchInterval: 60000, // Refetch every 60 seconds
    staleTime: 30000, // Consider stale after 30 seconds
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
