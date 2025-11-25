import type { SwitchboardAggregator } from "@/lib/types";

import { useState, useEffect } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:switchboard-aggregators");

const SWITCHBOARD_AGGREGATOR_TYPE_ID =
  import.meta.env.VITE_SWITCHBOARD_AGGREGATOR_TYPE_ID || "";
const GRAPHQL_URL = import.meta.env.VITE_SUI_GRAPHQL_URL || "";

interface GraphQLResponse {
  data?: {
    objects?: {
      nodes?: Array<{
        address: string;
        digest: string;
        asMoveObject?: {
          contents?: {
            json?: {
              name: string;
              id: string;
              authority: string;
              created_at_ms: string;
              current_result?: {
                result: {
                  value: string;
                  neg: boolean;
                };
                timestamp_ms: string;
              };
            };
          };
        };
      }>;
      pageInfo?: {
        hasNextPage: boolean;
        endCursor: string | null;
      };
    };
  };
  errors?: Array<{ message: string }>;
}

interface UseSwitchboardAggregatorsOptions {
  limit?: number;
  cursor?: string | null;
}

/**
 * Hook to query Switchboard Aggregator objects using GraphQL
 * Supports pagination
 */
export function useSwitchboardAggregators(
  options: UseSwitchboardAggregatorsOptions = {},
) {
  const { limit = 20, cursor = null } = options;
  const [aggregators, setAggregators] = useState<SwitchboardAggregator[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isFetching, setIsFetching] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [pagination, setPagination] = useState<{
    hasNextPage: boolean;
    nextCursor: string | null;
  }>({
    hasNextPage: false,
    nextCursor: null,
  });

  useEffect(() => {
    async function fetchAggregators() {
      if (!SWITCHBOARD_AGGREGATOR_TYPE_ID) {
        debugLog("SWITCHBOARD_AGGREGATOR_TYPE_ID not set, skipping query");
        setIsLoading(false);

        return;
      }

      setIsLoading(true);
      setIsFetching(true);
      setError(null);

      try {
        const query = `
          query ($cursor: String) {
            objects(
              first: ${limit}
              after: $cursor
              filter: {
                type: "${SWITCHBOARD_AGGREGATOR_TYPE_ID}"
              }
            ) {
              nodes {
                address
                digest
                asMoveObject {
                  contents {
                    json
                  }
                }
              }
              pageInfo {
                hasNextPage
                endCursor
              }
            }
          }
        `;

        const response = await fetch(GRAPHQL_URL, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            query,
            variables: { cursor },
          }),
        });

        if (!response.ok) {
          throw new Error(`GraphQL request failed: ${response.statusText}`);
        }

        const result: GraphQLResponse = await response.json();

        if (result.errors && result.errors.length > 0) {
          throw new Error(
            `GraphQL errors: ${result.errors.map((e) => e.message).join(", ")}`,
          );
        }

        const nodes = result.data?.objects?.nodes || [];
        const pageInfo = result.data?.objects?.pageInfo;

        const fetchedAggregators: SwitchboardAggregator[] = [];

        for (const node of nodes) {
          const json = node.asMoveObject?.contents?.json;

          if (json) {
            fetchedAggregators.push({
              id: json.id || node.address,
              name: json.name || "Unknown",
              address: node.address,
              authority: json.authority || "",
              created_at_ms: json.created_at_ms || "0",
              current_result: json.current_result
                ? {
                    result: {
                      value: json.current_result.result.value || "0",
                      neg: json.current_result.result.neg || false,
                    },
                    timestamp_ms: json.current_result.timestamp_ms || "0",
                  }
                : undefined,
            });
          }
        }

        debugLog(
          "Fetched %d Switchboard aggregators (page)",
          fetchedAggregators.length,
        );
        setAggregators(fetchedAggregators);
        setPagination({
          hasNextPage: pageInfo?.hasNextPage || false,
          nextCursor: pageInfo?.endCursor || null,
        });
      } catch (err) {
        errorLog("Error fetching Switchboard aggregators: %O", err);
        setError(err instanceof Error ? err : new Error(String(err)));
      } finally {
        setIsLoading(false);
        setIsFetching(false);
      }
    }

    fetchAggregators();
  }, [limit, cursor]);

  return { aggregators, isLoading, isFetching, error, pagination };
}
