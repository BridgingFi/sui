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

  // Extract deposit_fee_rate from vault object
  let depositFeeRate: number | null = null;
  let totalShares: bigint | null = null;

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

        if (feeRate !== undefined) {
          depositFeeRate = Number(feeRate);
        }
        if (shares !== undefined) {
          totalShares = BigInt(String(shares));
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
    isLoading: isLoadingVault || isLoadingShareRatio,
    error: vaultError,
    refetch: () => {
      refetchVault();
      refetchShareRatio();
    },
  };
}
