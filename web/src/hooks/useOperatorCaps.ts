import {
  useSuiClientQuery,
  useCurrentAccount,
  useCurrentWallet,
} from "@mysten/dapp-kit";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:operator-caps");

// Use initial package ID for querying objects (object addresses don't change after upgrade)
const VOLO_VAULT_PACKAGE_ID =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_INITIAL || "";

export interface OperatorCap {
  objectId: string;
  type: string;
}

/**
 * Hook to query user's OperatorCap objects
 * OperatorCap type: volo_vault::vault::OperatorCap
 * Returns loading state while wallet is connecting or not connected
 * @param enabled - Whether to enable the query (default: true)
 */
export function useOperatorCaps(enabled: boolean = true) {
  const currentAccount = useCurrentAccount();
  const { isConnected } = useCurrentWallet();

  // If wallet is not connected or account is not available, return loading state
  // This handles the auto-connecting case where account might be null temporarily
  const isWalletReady = isConnected && !!currentAccount;

  const {
    data: operatorCapsData,
    isLoading: isQueryLoading,
    isFetching,
    error,
    refetch,
  } = useSuiClientQuery(
    "getOwnedObjects",
    {
      owner: currentAccount?.address || "",
      filter: {
        StructType: `${VOLO_VAULT_PACKAGE_ID}::vault::OperatorCap`,
      },
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled: enabled && isWalletReady && !!VOLO_VAULT_PACKAGE_ID,
      staleTime: 30000, // Consider data fresh for 30 seconds
    },
  );

  // Return loading state if wallet is not ready or query is loading
  const isLoading = !isWalletReady || isQueryLoading;

  // Parse OperatorCap objects
  const operatorCaps: OperatorCap[] = useMemo(() => {
    if (!operatorCapsData?.data) {
      return [];
    }

    const caps: OperatorCap[] = [];

    operatorCapsData.data.forEach((obj) => {
      if (obj.data?.objectId && obj.data?.type) {
        caps.push({
          objectId: obj.data.objectId,
          type: obj.data.type,
        });
      }
    });

    debugLog(
      "Parsed OperatorCap objects count:%d objectIds:%o",
      caps.length,
      caps.map((c) => c.objectId),
    );

    return caps;
  }, [operatorCapsData]);

  // Log errors if present
  if (error) {
    errorLog("Error querying OperatorCap objects %O", error);
  }

  return {
    operatorCaps,
    isLoading,
    isFetching,
    error,
    refetch,
  };
}
