import type { VaultInfo } from "@/lib/types";

import { useSuiClientQuery } from "@mysten/dapp-kit";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:vault-registry");

const VAULT_REGISTRY_ID = import.meta.env.VITE_VAULT_REGISTRY_ID;

/**
 * Hook to query vault registry and get all registered vaults
 */
export function useVaultRegistry() {
  const {
    data: registryData,
    isLoading,
    isFetching,
    error,
    refetch,
  } = useSuiClientQuery(
    "getObject",
    {
      id: VAULT_REGISTRY_ID,
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled:
        !!VAULT_REGISTRY_ID &&
        VAULT_REGISTRY_ID !==
          "0x0000000000000000000000000000000000000000000000000000000000000000",
      staleTime: Infinity, // Data is considered fresh indefinitely until manually refreshed
    },
  );

  // Parse vault list from registry data
  // VecMap structure: { fields: { contents: [{ fields: { key: address, value: VaultInfo } }] } }
  // useMemo ensures vaults array reference stability, preventing unnecessary re-renders
  // of components that receive vaults as props
  const vaults: VaultInfo[] = useMemo(() => {
    const result: VaultInfo[] = [];

    if (registryData?.data && "content" in registryData.data) {
      const content = registryData.data.content;

      if (
        content &&
        "dataType" in content &&
        content.dataType === "moveObject" &&
        "fields" in content
      ) {
        const fields = content.fields as Record<string, unknown>;
        const vaultsMap = fields.vaults as unknown;

        if (
          vaultsMap &&
          typeof vaultsMap === "object" &&
          "fields" in vaultsMap
        ) {
          const vaultsMapFields = (vaultsMap as { fields: unknown }).fields;

          if (
            vaultsMapFields &&
            typeof vaultsMapFields === "object" &&
            "contents" in vaultsMapFields
          ) {
            const contents = (vaultsMapFields as { contents: unknown[] })
              .contents;

            if (Array.isArray(contents)) {
              contents.forEach((entry) => {
                if (entry && typeof entry === "object" && "fields" in entry) {
                  const entryFields = (entry as { fields: unknown }).fields;

                  if (
                    entryFields &&
                    typeof entryFields === "object" &&
                    "value" in entryFields
                  ) {
                    const valueObj = (entryFields as { value: unknown }).value;

                    // valueObj has structure: { type: "...", fields: { ... } }
                    if (
                      valueObj &&
                      typeof valueObj === "object" &&
                      "fields" in valueObj
                    ) {
                      const vaultFields = (
                        valueObj as { fields: Record<string, unknown> }
                      ).fields;

                      if (
                        vaultFields &&
                        "vault_id" in vaultFields &&
                        "reward_manager_id" in vaultFields &&
                        "coin_type" in vaultFields &&
                        "created_at_ms" in vaultFields &&
                        "creator" in vaultFields
                      ) {
                        // Convert coin_type from byte array to string
                        const coinTypeBytes = vaultFields.coin_type as number[];
                        const coinType = Array.isArray(coinTypeBytes)
                          ? String.fromCharCode(...coinTypeBytes)
                          : String(vaultFields.coin_type);

                        const vaultInfo: VaultInfo = {
                          vault_id: String(vaultFields.vault_id),
                          reward_manager_id: String(
                            vaultFields.reward_manager_id,
                          ),
                          coin_type: coinType,
                          created_at_ms: Number(vaultFields.created_at_ms),
                          creator: String(vaultFields.creator),
                        };

                        result.push(vaultInfo);
                      }
                    }
                  }
                }
              });
            }
          }
        }
      }
    }

    // Log parsing result
    debugLog(
      "Parsed vault registry vaultCount:%d vaultIds:%o",
      result.length,
      result.map((v) => v.vault_id).sort(),
    );

    return result;
  }, [registryData]);

  // Log errors if present
  if (error) {
    errorLog("Error querying vault registry %O", error);
  }

  return {
    vaults,
    isLoading,
    isFetching,
    error,
    refetch,
    registryId: VAULT_REGISTRY_ID,
  };
}
