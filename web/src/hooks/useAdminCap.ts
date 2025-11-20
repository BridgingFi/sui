import {
  useSuiClientQuery,
  useCurrentAccount,
  useCurrentWallet,
} from "@mysten/dapp-kit";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:admin-cap");

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";

export interface AdminCap {
  objectId: string;
  type: string;
}

/**
 * Hook to check if user has AdminCap
 * AdminCap type: volo_vault::vault::AdminCap
 * Returns loading state while wallet is connecting or not connected
 */
export function useAdminCap() {
  const currentAccount = useCurrentAccount();
  const { isConnected } = useCurrentWallet();

  // If wallet is not connected or account is not available, return loading state
  // This handles the auto-connecting case where account might be null temporarily
  const isWalletReady = isConnected && !!currentAccount;

  const {
    data: adminCapData,
    isLoading: isQueryLoading,
    isFetching,
    error,
    refetch,
  } = useSuiClientQuery(
    "getOwnedObjects",
    {
      owner: currentAccount?.address || "",
      filter: {
        StructType: `${VOLO_VAULT_PACKAGE_ID}::vault::AdminCap`,
      },
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled: isWalletReady && !!VOLO_VAULT_PACKAGE_ID,
      staleTime: 60000, // Consider data fresh for 60 seconds (AdminCap rarely changes)
    },
  );

  // Return loading state if wallet is not ready or query is loading
  const isLoading = !isWalletReady || isQueryLoading;

  // Check if user has AdminCap
  const hasAdminCap = useMemo(() => {
    const hasCap = (adminCapData?.data?.length || 0) > 0;

    debugLog(
      "AdminCap check hasAdminCap:%s objectCount:%d",
      hasCap,
      adminCapData?.data?.length || 0,
    );

    return hasCap;
  }, [adminCapData]);

  // Get first AdminCap object ID if exists
  const adminCap: AdminCap | null = useMemo(() => {
    if (!adminCapData?.data || adminCapData.data.length === 0) {
      return null;
    }

    const firstObj = adminCapData.data[0];

    if (firstObj?.data?.objectId && firstObj.data.type) {
      return {
        objectId: firstObj.data.objectId,
        type: firstObj.data.type,
      };
    }

    return null;
  }, [adminCapData]);

  // Log errors if present
  if (error) {
    errorLog("Error querying AdminCap objects %O", error);
  }

  return {
    hasAdminCap,
    adminCap,
    isLoading,
    isFetching,
    error,
    refetch,
  };
}
