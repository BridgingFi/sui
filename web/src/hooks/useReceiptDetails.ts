import { useSuiClient } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";

export interface ReceiptDetails {
  receiptId: string;
  vaultId: string;
  status: number; // 0: normal, 1: pending_deposit, 2: pending_withdraw, 3: pending_withdraw_with_auto_transfer
  shares: string;
  pendingDepositBalance: string;
  pendingWithdrawShares: string;
  claimablePrincipal: string;
  lastDepositTime: number;
}

/**
 * Hook to query and cache receipts table ID for a vault
 * The receipts table ID is fixed once the vault is created, so it can be cached
 *
 * @param vaultId - The vault object ID
 */
function useReceiptsTableId(vaultId: string | null) {
  const client = useSuiClient();

  const {
    data: receiptsTableId,
    isLoading,
    error,
  } = useQuery({
    queryKey: ["receipts-table-id", vaultId],
    queryFn: async (): Promise<string | null> => {
      if (!vaultId) {
        return null;
      }

      try {
        const vaultData = await client.getObject({
          id: vaultId,
          options: {
            showContent: true,
          },
        });

        if (
          !vaultData.data ||
          !("content" in vaultData.data) ||
          !vaultData.data.content ||
          vaultData.data.content.dataType !== "moveObject" ||
          !("fields" in vaultData.data.content)
        ) {
          return null;
        }

        const vaultFields = vaultData.data.content.fields as Record<
          string,
          unknown
        >;

        // Extract receipts table ID from vault object
        // Structure: vault.fields.receipts.fields.id.id
        const receiptsTable = vaultFields.receipts as Record<string, unknown>;

        if (!receiptsTable || typeof receiptsTable !== "object") {
          return null;
        }

        const receiptsTableFields = (receiptsTable as Record<string, unknown>)
          .fields as Record<string, unknown>;

        if (!receiptsTableFields || typeof receiptsTableFields !== "object") {
          return null;
        }

        const receiptsTableIdObj = receiptsTableFields.id as Record<
          string,
          unknown
        >;

        if (!receiptsTableIdObj || typeof receiptsTableIdObj !== "object") {
          return null;
        }

        const tableId = receiptsTableIdObj.id as string;

        return tableId || null;
      } catch {
        return null;
      }
    },
    enabled: !!vaultId,
    staleTime: Infinity, // Table ID never changes, cache forever
    gcTime: Infinity, // Keep in cache forever
  });

  return {
    receiptsTableId: receiptsTableId || null,
    isLoading,
    error,
  };
}

/**
 * Hook to query receipt details from vault's receipts table
 * Queries VaultReceiptInfo for a specific receipt
 *
 * @param vaultId - The vault object ID
 * @param receiptId - The receipt object ID
 */
export function useReceiptDetails(
  vaultId: string | null,
  receiptId: string | null,
) {
  const client = useSuiClient();
  const {
    receiptsTableId,
    isLoading: isLoadingTableId,
    error: tableIdError,
  } = useReceiptsTableId(vaultId);

  const {
    data: details,
    isLoading: isLoadingDetails,
    error: detailsError,
    refetch,
  } = useQuery({
    queryKey: ["receipt-details", vaultId, receiptId],
    queryFn: async (): Promise<ReceiptDetails | null> => {
      // receiptsTableId is guaranteed to be non-null here because enabled check
      // But TypeScript doesn't know that, so we use non-null assertion
      if (!receiptsTableId) {
        return null;
      }

      try {
        // Query dynamic field from receipts table
        // The dynamic field structure is: { name: address, value: VaultReceiptInfo }
        const dynamicField = await client.getDynamicFieldObject({
          parentId: receiptsTableId,
          name: {
            type: "address",
            value: receiptId,
          },
        });

        if (
          !dynamicField.data ||
          !("content" in dynamicField.data) ||
          !dynamicField.data.content ||
          dynamicField.data.content.dataType !== "moveObject" ||
          !("fields" in dynamicField.data.content)
        ) {
          return null;
        }

        const dynamicFields = dynamicField.data.content.fields as Record<
          string,
          unknown
        >;

        // Extract VaultReceiptInfo from value.fields
        // The dynamic field structure is: { name: address, value: VaultReceiptInfo }
        const valueFields =
          ((dynamicFields.value as Record<string, unknown>)?.fields as Record<
            string,
            unknown
          >) || dynamicFields;

        // Parse VaultReceiptInfo fields
        const status = Number(valueFields.status || 0);
        const shares = String(valueFields.shares || "0");
        const pendingDepositBalance = String(
          valueFields.pending_deposit_balance || "0",
        );
        const pendingWithdrawShares = String(
          valueFields.pending_withdraw_shares || "0",
        );
        const claimablePrincipal = String(
          valueFields.claimable_principal || "0",
        );
        const lastDepositTime = Number(valueFields.last_deposit_time || 0);

        return {
          receiptId: receiptId!,
          vaultId: vaultId!,
          status,
          shares,
          pendingDepositBalance,
          pendingWithdrawShares,
          claimablePrincipal,
          lastDepositTime,
        };
      } catch {
        return null;
      }
    },
    enabled:
      !!vaultId && !!receiptId && !!VOLO_VAULT_PACKAGE_ID && !!receiptsTableId,
    refetchInterval: 30000, // Refetch every 30 seconds
  });

  return {
    details: details || null,
    isLoading: isLoadingTableId || isLoadingDetails,
    error: tableIdError || detailsError,
    refetch,
  };
}

/**
 * Hook to query all receipt details for a vault
 * Queries multiple receipts at once
 *
 * @param vaultId - The vault object ID
 * @param receiptIds - Array of receipt object IDs
 */
export function useReceiptDetailsBatch(
  vaultId: string | null,
  receiptIds: string[],
) {
  const client = useSuiClient();
  const {
    receiptsTableId,
    isLoading: isLoadingTableId,
    error: tableIdError,
  } = useReceiptsTableId(vaultId);

  const {
    data: detailsMap,
    isLoading: isLoadingDetails,
    error: detailsError,
    refetch,
  } = useQuery({
    queryKey: ["receipt-details-batch", vaultId, receiptIds.join(",")],
    queryFn: async (): Promise<Record<string, ReceiptDetails | null>> => {
      // receiptsTableId is guaranteed to be non-null here because enabled check
      if (!receiptsTableId) {
        return {};
      }

      const result: Record<string, ReceiptDetails | null> = {};

      // Query all receipts in parallel using cached receipts table ID
      await Promise.all(
        receiptIds.map(async (receiptId) => {
          try {
            // Use dynamic field API to query receipt info from receipts table
            // The receipts table stores VaultReceiptInfo by receipt_id
            const dynamicField = await client.getDynamicFieldObject({
              parentId: receiptsTableId!,
              name: {
                type: "address",
                value: receiptId,
              },
            });

            if (
              dynamicField.data &&
              "content" in dynamicField.data &&
              dynamicField.data.content &&
              dynamicField.data.content.dataType === "moveObject" &&
              "fields" in dynamicField.data.content
            ) {
              const dynamicFields = dynamicField.data.content.fields as Record<
                string,
                unknown
              >;

              // Extract VaultReceiptInfo from value.fields
              // The dynamic field structure is: { name: address, value: VaultReceiptInfo }
              const valueFields =
                ((dynamicFields.value as Record<string, unknown>)
                  ?.fields as Record<string, unknown>) || dynamicFields;

              // Parse VaultReceiptInfo fields
              const status = Number(valueFields.status || 0);
              const shares = String(valueFields.shares || "0");
              const pendingDepositBalance = String(
                valueFields.pending_deposit_balance || "0",
              );
              const pendingWithdrawShares = String(
                valueFields.pending_withdraw_shares || "0",
              );
              const claimablePrincipal = String(
                valueFields.claimable_principal || "0",
              );
              const lastDepositTime = Number(
                valueFields.last_deposit_time || 0,
              );

              result[receiptId] = {
                receiptId: receiptId!,
                vaultId: vaultId!,
                status,
                shares,
                pendingDepositBalance,
                pendingWithdrawShares,
                claimablePrincipal,
                lastDepositTime,
              };
            } else {
              result[receiptId] = null;
            }
          } catch {
            result[receiptId] = null;
          }
        }),
      );

      return result;
    },
    enabled:
      !!vaultId &&
      receiptIds.length > 0 &&
      !!VOLO_VAULT_PACKAGE_ID &&
      !!receiptsTableId,
    refetchInterval: 30000,
  });

  return {
    detailsMap: detailsMap || {},
    isLoading: isLoadingTableId || isLoadingDetails,
    error: tableIdError || detailsError,
    refetch,
  };
}
