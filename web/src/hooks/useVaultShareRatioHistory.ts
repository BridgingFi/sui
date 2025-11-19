import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";

export interface ShareRatioHistoryItem {
  shareRatio: bigint;
  timestamp: number;
  transactionDigest: string;
}

/**
 * Hook to query share ratio history from ShareRatioUpdated events
 * Returns historical share ratio data for chart/table display
 *
 * @param vaultId - The vault object ID
 * @param limit - Maximum number of events to fetch (default: 50)
 */
export function useVaultShareRatioHistory(
  vaultId: string | null,
  limit: number = 50,
) {
  const client = useSuiClient();

  const {
    data: history,
    isLoading,
    error,
    refetch,
  } = useQuery({
    queryKey: ["vault-share-ratio-history", vaultId, limit],
    queryFn: async (): Promise<ShareRatioHistoryItem[]> => {
      if (!vaultId || !VOLO_VAULT_PACKAGE_ID) {
        return [];
      }

      try {
        // Query ShareRatioUpdated events for this vault
        const eventType = `${VOLO_VAULT_PACKAGE_ID}::vault::ShareRatioUpdated`;

        const events = await client.queryEvents({
          query: {
            MoveEventType: eventType,
          },
          limit,
          order: "descending", // Most recent first
        });

        if (!events.data || events.data.length === 0) {
          return [];
        }

        // Filter events by vault_id and parse them
        const historyItems: ShareRatioHistoryItem[] = [];

        for (const event of events.data) {
          if (
            event.parsedJson &&
            typeof event.parsedJson === "object" &&
            "vault_id" in event.parsedJson
          ) {
            const eventVaultId = String(event.parsedJson.vault_id);

            // Only include events for this vault
            if (eventVaultId === vaultId) {
              const parsedJson = event.parsedJson as Record<string, unknown>;
              const shareRatioValue = parsedJson.share_ratio;
              const timestampValue = parsedJson.timestamp;

              if (shareRatioValue !== undefined) {
                let shareRatio: bigint;

                // Convert share_ratio (u256) to BigInt
                if (typeof shareRatioValue === "string") {
                  shareRatio = BigInt(shareRatioValue);
                } else if (typeof shareRatioValue === "number") {
                  shareRatio = BigInt(shareRatioValue);
                } else if (Array.isArray(shareRatioValue)) {
                  // If it's an array (bytes representation), convert it
                  shareRatio = 0n;

                  for (let i = shareRatioValue.length - 1; i >= 0; i--) {
                    shareRatio =
                      shareRatio * 256n + BigInt(shareRatioValue[i] || 0);
                  }
                } else {
                  continue; // Skip invalid data
                }

                // Parse timestamp
                let timestamp = 0;

                if (timestampValue !== undefined) {
                  if (typeof timestampValue === "string") {
                    timestamp = Number(timestampValue);
                  } else if (typeof timestampValue === "number") {
                    timestamp = timestampValue;
                  }
                }

                // Fallback to event timestamp if available
                if (timestamp === 0 && event.timestampMs) {
                  timestamp = Number(event.timestampMs);
                }

                historyItems.push({
                  shareRatio,
                  timestamp,
                  transactionDigest: event.id.txDigest,
                });
              }
            }
          }
        }

        // Sort by timestamp descending (most recent first)
        return historyItems.sort((a, b) => b.timestamp - a.timestamp);
      } catch {
        // Silently fail - events might not be available
        return [];
      }
    },
    enabled: !!vaultId && !!VOLO_VAULT_PACKAGE_ID,
    refetchInterval: 60000, // Refetch every 60 seconds (less frequent than real-time query)
    staleTime: 30000, // Consider data stale after 30 seconds
  });

  return {
    history: history || [],
    isLoading,
    error,
    refetch,
  };
}
