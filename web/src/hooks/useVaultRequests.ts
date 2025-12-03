import { useSuiClientQuery } from "@mysten/dapp-kit";
import { useQueryClient } from "@tanstack/react-query";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:vault-requests");

const VOLO_VAULT_PACKAGE_ID =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_INITIAL || "";

// Query keys for React Query
export const VAULT_REQUEST_SIZES_QUERY_KEY = ["vaultRequestSizes"] as const;

interface VaultTableIds {
  depositRequestsTableId: string;
  withdrawRequestsTableId: string;
}

interface VaultRequestSizes {
  depositRequestsSize: number;
  withdrawRequestsSize: number;
}

// Raw field types from Move objects (used directly without conversion)
export interface DepositRequest {
  request_id: number | string;
  receipt_id: string;
  recipient: string;
  vault_id: string;
  amount: number | string;
  expected_shares: string | number;
  request_time: number | string;
}

export interface WithdrawRequest {
  request_id: number | string;
  receipt_id: string;
  recipient: string;
  vault_id: string;
  shares: string | number;
  expected_amount: number | string;
  request_time: number | string;
}

export interface DepositRequestsOptions {
  limit?: number;
  cursor?: string;
}

export interface WithdrawRequestsOptions {
  limit?: number;
  cursor?: string;
}

export interface DepositRequestsResult {
  requests: DepositRequest[];
  pagination: {
    hasNextPage: boolean;
    nextCursor?: string;
  };
}

export interface WithdrawRequestsResult {
  requests: WithdrawRequest[];
  pagination: {
    hasNextPage: boolean;
    nextCursor?: string;
  };
}

/**
 * Hook to get cached vault table IDs
 * Table IDs never change for a vault, so we cache them permanently
 */
function useVaultTableIds(vaultId: string | null) {
  const {
    data: vaultObject,
    isLoading,
    isFetching,
    error,
    refetch,
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
      staleTime: Infinity, // Table IDs never change
    },
  );

  // Extract table IDs from vault object
  // useMemo ensures data reference stability
  const data: VaultTableIds | null = useMemo(() => {
    if (
      !vaultObject?.data ||
      !("content" in vaultObject.data) ||
      vaultObject.data.content?.dataType !== "moveObject" ||
      !("fields" in vaultObject.data.content)
    ) {
      debugLog(
        "Failed to get vault object or invalid structure vaultId:%s",
        vaultId || "null",
      );

      return null;
    }

    const vaultFields = vaultObject.data.content.fields as Record<
      string,
      unknown
    >;

    // Extract request_buffer from vault fields
    const requestBuffer = vaultFields.request_buffer as
      | {
          fields?: {
            deposit_requests?: {
              fields?: { id?: { id?: string }; size?: string | number };
            };
            withdraw_requests?: {
              fields?: { id?: { id?: string }; size?: string | number };
            };
          };
        }
      | undefined;

    if (!requestBuffer?.fields) {
      debugLog(
        "No request_buffer found in vault vaultId:%s",
        vaultId || "null",
      );

      return null;
    }

    const depositRequestsTable = requestBuffer.fields.deposit_requests?.fields;
    const withdrawRequestsTable =
      requestBuffer.fields.withdraw_requests?.fields;

    const depositRequestsTableId =
      depositRequestsTable?.id?.id ||
      (depositRequestsTable as { id?: string })?.id;
    const withdrawRequestsTableId =
      withdrawRequestsTable?.id?.id ||
      (withdrawRequestsTable as { id?: string })?.id;

    if (!depositRequestsTableId || !withdrawRequestsTableId) {
      debugLog(
        "Failed to extract table IDs vaultId:%s depositTableId:%s withdrawTableId:%s",
        vaultId || "null",
        depositRequestsTableId || "null",
        withdrawRequestsTableId || "null",
      );

      return null;
    }

    debugLog(
      "Extracted table IDs vaultId:%s depositTableId:%s withdrawTableId:%s",
      vaultId || "null",
      depositRequestsTableId,
      withdrawRequestsTableId,
    );

    return {
      depositRequestsTableId,
      withdrawRequestsTableId,
    };
  }, [vaultObject, vaultId]);

  // Log errors if present
  if (error) {
    errorLog(
      "Error querying vault table IDs vaultId:%s %O",
      vaultId || "null",
      error,
    );
  }

  return {
    data,
    isLoading,
    isFetching,
    error,
    refetch,
  };
}

/**
 * Hook to get vault request sizes
 * Manual refresh is available via refetch
 */
export function useVaultRequestSizes(vaultId: string | null) {
  const {
    data: vaultObject,
    isLoading,
    isFetching,
    error,
    refetch,
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
      staleTime: Infinity, // Data is considered fresh indefinitely until manually refreshed
    },
  );

  // Extract request sizes from vault object
  // useMemo ensures data reference stability
  const data: VaultRequestSizes | null = useMemo(() => {
    if (
      !vaultObject?.data ||
      !("content" in vaultObject.data) ||
      vaultObject.data.content?.dataType !== "moveObject" ||
      !("fields" in vaultObject.data.content)
    ) {
      debugLog(
        "Failed to get vault object or invalid structure vaultId:%s",
        vaultId || "null",
      );

      return null;
    }

    const vaultFields = vaultObject.data.content.fields as Record<
      string,
      unknown
    >;

    // Extract request_buffer from vault fields
    const requestBuffer = vaultFields.request_buffer as
      | {
          fields?: {
            deposit_requests?: {
              fields?: { size?: string | number };
            };
            withdraw_requests?: {
              fields?: { size?: string | number };
            };
          };
        }
      | undefined;

    if (!requestBuffer?.fields) {
      debugLog(
        "No request_buffer found in vault vaultId:%s",
        vaultId || "null",
      );

      return null;
    }

    const depositRequestsTable = requestBuffer.fields.deposit_requests?.fields;
    const withdrawRequestsTable =
      requestBuffer.fields.withdraw_requests?.fields;

    // Extract table sizes
    const depositRequestsSize = Number(depositRequestsTable?.size || 0);
    const withdrawRequestsSize = Number(withdrawRequestsTable?.size || 0);

    debugLog(
      "Extracted request sizes vaultId:%s depositSize:%d withdrawSize:%d",
      vaultId || "null",
      depositRequestsSize,
      withdrawRequestsSize,
    );

    return {
      depositRequestsSize,
      withdrawRequestsSize,
    };
  }, [vaultObject, vaultId]);

  // Log errors if present
  if (error) {
    errorLog(
      "Error querying vault request sizes vaultId:%s %O",
      vaultId || "null",
      error,
    );
  }

  return {
    data,
    isLoading,
    isFetching,
    error,
    refetch,
  };
}

/**
 * Hook to invalidate all vault request sizes
 * Invalidates all vault request size queries, causing them to refetch
 */
export function useInvalidateVaultRequestSizes() {
  const queryClient = useQueryClient();

  return () => {
    queryClient.invalidateQueries({ queryKey: VAULT_REQUEST_SIZES_QUERY_KEY });
  };
}

/**
 * Generic hook to query requests (deposit or withdraw) for a vault
 * Uses dynamic fields to query requests directly from vault's request_buffer
 * This is more real-time than querying events
 * Supports pagination
 * Uses cached table IDs to avoid refetching vault object
 */
function useRequestList<
  TRequest extends DepositRequest | WithdrawRequest,
  TRequestType extends TRequest extends DepositRequest ? "deposit" : "withdraw",
>(
  vaultId: string | null,
  tableId: string | undefined,
  options: DepositRequestsOptions | WithdrawRequestsOptions,
  requestType: TRequestType,
): {
  data: {
    requests: TRequest[];
    pagination: {
      hasNextPage: boolean;
      nextCursor?: string;
    };
  };
  isLoading: boolean;
  isFetching: boolean;
  error: Error | null;
  refetch: () => void;
} {
  const { limit = 50, cursor } = options;

  // Step 1: Query dynamic fields
  const {
    data: fieldsResult,
    isLoading: isLoadingFields,
    isFetching: isFetchingFields,
    error: fieldsError,
    refetch: refetchFields,
  } = useSuiClientQuery(
    "getDynamicFields",
    {
      parentId: tableId || "",
      cursor,
      limit,
    },
    {
      enabled: !!vaultId && !!VOLO_VAULT_PACKAGE_ID && !!tableId,
    },
  );

  // Extract field IDs from dynamic fields result
  const fieldIds = fieldsResult?.data.map((field) => field.objectId) || [];

  // Step 2: Fetch request objects
  const {
    data: objects,
    isLoading: isLoadingObjects,
    isFetching: isFetchingObjects,
    error: objectsError,
    refetch: refetchObjects,
  } = useSuiClientQuery(
    "multiGetObjects",
    {
      ids: fieldIds,
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled: fieldIds.length > 0,
    },
  );

  // Parse requests from objects
  const data = useMemo(() => {
    if (!objects || objects.length === 0) {
      return {
        requests: [],
        pagination: {
          hasNextPage: fieldsResult?.hasNextPage || false,
          nextCursor: fieldsResult?.nextCursor || undefined,
        },
      };
    }

    const requests: TRequest[] = [];

    objects.forEach((obj) => {
      if (
        obj.data &&
        "content" in obj.data &&
        obj.data.content?.dataType === "moveObject" &&
        "fields" in obj.data.content
      ) {
        const fields = obj.data.content.fields as Record<string, unknown>;
        // The structure is: { name: u64, value: Request }
        const value = fields.value as
          | {
              fields: DepositRequest | WithdrawRequest;
            }
          | undefined;

        if (value?.fields) {
          const requestFields = value.fields;

          // Validate vault_id matches (defensive check, should always match since table is vault-specific)
          if (requestFields.vault_id !== vaultId || !vaultId) {
            if (requestFields.vault_id !== vaultId) {
              errorLog(
                "Request vault_id mismatch expected:%s actual:%s requestId:%s",
                vaultId || "null",
                requestFields.vault_id || "null",
                requestFields.request_id || "null",
              );
            }

            return;
          }

          requests.push(requestFields as TRequest);
        }
      }
    });

    // Sort by request_id descending (newest first)
    requests.sort((a, b) => {
      const aId = Number(a.request_id);
      const bId = Number(b.request_id);

      return bId - aId;
    });

    debugLog(
      "Parsed %s requests vaultId:%s limit:%d cursor:%s requestsCount:%d fieldIdsCount:%d hasNextPage:%s nextCursor:%s",
      requestType,
      vaultId || "null",
      limit,
      cursor || "null",
      requests.length,
      fieldIds.length,
      fieldsResult?.hasNextPage || false,
      fieldsResult?.nextCursor || "null",
    );

    return {
      requests,
      pagination: {
        hasNextPage: fieldsResult?.hasNextPage || false,
        nextCursor: fieldsResult?.nextCursor || undefined,
      },
    };
  }, [objects, fieldsResult, vaultId, limit, cursor]);

  // Log errors if present
  if (fieldsError) {
    errorLog(
      "Error querying %s request fields vaultId:%s limit:%d cursor:%s %O",
      requestType,
      vaultId || "null",
      limit,
      cursor || "null",
      fieldsError,
    );
  }

  if (objectsError) {
    errorLog(
      "Error querying %s request objects vaultId:%s %O",
      requestType,
      vaultId || "null",
      objectsError,
    );
  }

  return {
    data,
    isLoading: isLoadingFields || isLoadingObjects,
    isFetching: isFetchingFields || isFetchingObjects,
    error: fieldsError || objectsError,
    refetch: () => {
      refetchFields();
      refetchObjects();
    },
  };
}

/**
 * Hook to query deposit requests for a specific vault
 * Uses dynamic fields to query requests directly from vault's request_buffer
 * This is more real-time than querying events
 * Supports pagination
 * Uses cached table IDs to avoid refetching vault object
 */
export function useDepositRequests(
  vaultId: string | null,
  options: DepositRequestsOptions = {},
) {
  const { data: tableIds } = useVaultTableIds(vaultId);

  return useRequestList<DepositRequest, "deposit">(
    vaultId,
    tableIds?.depositRequestsTableId,
    options,
    "deposit",
  );
}

/**
 * Hook to query withdraw requests for a specific vault
 * Uses dynamic fields to query requests directly from vault's request_buffer
 * This is more real-time than querying events
 * Supports pagination
 * Uses cached table IDs to avoid refetching vault object
 */
export function useWithdrawRequests(
  vaultId: string | null,
  options: WithdrawRequestsOptions = {},
) {
  const { data: tableIds } = useVaultTableIds(vaultId);

  return useRequestList<WithdrawRequest, "withdraw">(
    vaultId,
    tableIds?.withdrawRequestsTableId,
    options,
    "withdraw",
  );
}
