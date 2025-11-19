import { useSuiClientQuery } from "@mysten/dapp-kit";
import { useCurrentAccount } from "@mysten/dapp-kit";

export interface UserReceipt {
  id: string;
  vaultId: string;
}

/**
 * Hook to query user's Receipt objects for a specific vault
 * Receipt type: volo_vault::receipt::Receipt
 */
export function useUserReceipts(vaultId: string | null) {
  const currentAccount = useCurrentAccount();

  const {
    data: receiptsData,
    isLoading,
    error,
    refetch,
  } = useSuiClientQuery(
    "getOwnedObjects",
    {
      owner: currentAccount?.address || "",
      filter: {
        StructType: `${import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || ""}::receipt::Receipt`,
      },
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled:
        !!currentAccount?.address &&
        !!import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID,
    },
  );

  // Filter receipts by vault_id
  // Receipt structure: { id: { id: address }, vault_id: address }
  const filteredReceipts: UserReceipt[] =
    receiptsData?.data
      ?.filter((obj) => {
        if (
          obj.data?.content &&
          "dataType" in obj.data.content &&
          obj.data.content.dataType === "moveObject" &&
          "fields" in obj.data.content
        ) {
          const fields = obj.data.content.fields as Record<string, unknown>;
          const receiptVaultId =
            typeof fields.vault_id === "string"
              ? fields.vault_id
              : typeof fields.vault_id === "object" &&
                  fields.vault_id !== null &&
                  "id" in fields.vault_id
                ? String((fields.vault_id as { id: string }).id)
                : null;

          return vaultId && receiptVaultId === vaultId;
        }
        return false;
      })
      .map((obj) => {
        if (
          obj.data?.content &&
          "dataType" in obj.data.content &&
          obj.data.content.dataType === "moveObject" &&
          "fields" in obj.data.content
        ) {
          const fields = obj.data.content.fields as Record<string, unknown>;
          const receiptVaultId =
            typeof fields.vault_id === "string"
              ? fields.vault_id
              : typeof fields.vault_id === "object" &&
                  fields.vault_id !== null &&
                  "id" in fields.vault_id
                ? String((fields.vault_id as { id: string }).id)
                : "";

          return {
            id: obj.data.objectId,
            vaultId: receiptVaultId,
          };
        }
        return null;
      })
      .filter((r): r is UserReceipt => r !== null) || [];

  return {
    receipts: filteredReceipts,
    isLoading,
    error,
    refetch,
  };
}


