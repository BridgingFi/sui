import {
  useSuiClientQuery,
  useCurrentAccount,
  useCurrentWallet,
} from "@mysten/dapp-kit";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:admin-cap");

// AdminCap object ID - use this to directly query if user owns the AdminCap
// This avoids issues with package upgrades where the type might change
const ADMIN_CAP_ID = import.meta.env.VITE_VOLO_VAULT_ADMINCAP_ID || "";

/**
 * Hook to check if user has AdminCap
 * Uses AdminCap object ID to directly query ownership
 * Returns loading state while wallet is connecting or not connected
 */
export function useAdminCap() {
  const currentAccount = useCurrentAccount();
  const { isConnected } = useCurrentWallet();

  // If wallet is not connected or account is not available, return loading state
  // This handles the auto-connecting case where account might be null temporarily
  const isWalletReady = isConnected && !!currentAccount;

  const {
    data: adminCapObject,
    isLoading: isQueryLoading,
    isFetching,
    error,
    refetch,
  } = useSuiClientQuery(
    "getObject",
    {
      id: ADMIN_CAP_ID,
      options: {
        showOwner: true,
      },
    },
    {
      enabled: isWalletReady && !!ADMIN_CAP_ID,
      staleTime: 60000, // Consider data fresh for 60 seconds (AdminCap rarely changes)
    },
  );

  // Return loading state if wallet is not ready or query is loading
  const isLoading = !isWalletReady || isQueryLoading;

  // Check if user owns the AdminCap
  const hasAdminCap = useMemo(() => {
    if (!adminCapObject?.data || !currentAccount?.address) {
      return false;
    }

    // Check if the object's owner matches the current account
    const owner = adminCapObject.data.owner;
    let isOwner = false;

    if (owner) {
      if (typeof owner === "string") {
        // AddressOwner case
        isOwner = owner === currentAccount.address;
      } else if ("AddressOwner" in owner) {
        isOwner = owner.AddressOwner === currentAccount.address;
      } else if ("ObjectOwner" in owner) {
        // ObjectOwner case - not owned by address
        isOwner = false;
      } else if ("Shared" in owner) {
        // Shared object - not owned by address
        isOwner = false;
      }
    }

    debugLog(
      "AdminCap check hasAdminCap:%s objectId:%s owner:%o currentAddress:%s",
      isOwner,
      ADMIN_CAP_ID,
      owner,
      currentAccount.address,
    );

    return isOwner;
  }, [adminCapObject, currentAccount?.address]);

  // Return AdminCap object ID if user owns it
  const adminCap = useMemo(() => {
    if (!hasAdminCap || !ADMIN_CAP_ID) {
      return null;
    }

    return {
      objectId: ADMIN_CAP_ID,
    };
  }, [hasAdminCap]);

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
