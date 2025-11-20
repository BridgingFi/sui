import { useSuiClient, useSuiClientQuery } from "@mysten/dapp-kit";
import { useQuery } from "@tanstack/react-query";
import { useMemo } from "react";
import { QueryEventsParams } from "@mysten/sui/client";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:all-operator-caps");

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";
const OPERATION_OBJECT_ID = import.meta.env.VITE_OPERATION_OBJECT_ID || "";

export interface OperatorCapInfo {
  objectId: string;
  owner: string | null;
  isFreezed: boolean;
}

export interface OperatorCapsOptions {
  limit?: number;
  cursor?: QueryEventsParams["cursor"];
}

/**
 * Hook to query OperatorCap objects created via events with pagination
 * Also checks if each OperatorCap is freezed in the Operation object
 */
export function useAllOperatorCaps(options: OperatorCapsOptions = {}) {
  const { limit = 20, cursor } = options;
  const client = useSuiClient();

  // Query OperatorCapCreated events with pagination using useSuiClientQuery
  const {
    data: eventsResult,
    isLoading: isLoadingEvents,
    isFetching: isFetchingEvents,
    error: eventsError,
    refetch: refetchEvents,
  } = useSuiClientQuery(
    "queryEvents",
    {
      query: {
        MoveEventType: `${VOLO_VAULT_PACKAGE_ID}::vault::OperatorCapCreated`,
      },
      limit,
      cursor,
      order: "descending",
    },
    {
      enabled: !!VOLO_VAULT_PACKAGE_ID,
      select: (events) => {
        if (!events.data || events.data.length === 0) {
          return {
            data: [],
            nextCursor: events.nextCursor,
            hasNextPage: events.hasNextPage || false,
          };
        }

        // Extract cap_id from events
        const capIds: string[] = [];

        for (const event of events.data) {
          if (
            event.parsedJson &&
            typeof event.parsedJson === "object" &&
            "cap_id" in event.parsedJson
          ) {
            const capId = String(event.parsedJson.cap_id);

            if (capId && !capIds.includes(capId)) {
              capIds.push(capId);
            }
          }
        }

        debugLog(
          "Found OperatorCap events count:%d uniqueCapIds:%d hasNextPage:%s nextCursor:%s",
          events.data.length,
          capIds.length,
          events.hasNextPage || false,
          events.nextCursor || "null",
        );

        return {
          data: capIds,
          nextCursor: events.nextCursor,
          hasNextPage: events.hasNextPage || false,
        };
      },
      staleTime: 60000, // Consider data fresh for 60 seconds
    },
  );

  const eventsData = eventsResult?.data || [];

  // Query Operation object to get freezed_operators
  const {
    data: operationData,
    isLoading: isLoadingOperation,
    error: operationError,
  } = useQuery({
    queryKey: ["operation-object", OPERATION_OBJECT_ID],
    queryFn: async () => {
      if (!OPERATION_OBJECT_ID) {
        return null;
      }

      try {
        const obj = await client.getObject({
          id: OPERATION_OBJECT_ID,
          options: {
            showContent: true,
            showType: true,
          },
        });

        if (
          obj.data &&
          "content" in obj.data &&
          obj.data.content?.dataType === "moveObject" &&
          "fields" in obj.data.content
        ) {
          const fields = obj.data.content.fields as Record<string, unknown>;
          const freezedOperators = fields.freezed_operators as
            | {
                fields?: {
                  id?: { id?: string };
                };
                id?: { id?: string };
              }
            | undefined;

          // Get Table ID
          const tableId =
            freezedOperators?.fields?.id?.id ||
            freezedOperators?.id?.id ||
            (freezedOperators as { id?: string })?.id;

          if (!tableId) {
            debugLog("No freezed_operators table ID found");

            return new Map<string, boolean>();
          }

          // Query dynamic fields of the Table to get all entries
          const dynamicFields = await client.getDynamicFields({
            parentId: tableId,
            limit: 1000,
          });

          const freezedMap = new Map<string, boolean>();

          if (dynamicFields.data && dynamicFields.data.length > 0) {
            // Get all field IDs
            const fieldIds = dynamicFields.data.map((field) => field.objectId);

            // Batch get all field objects
            const fieldObjects = await client.multiGetObjects({
              ids: fieldIds,
              options: {
                showContent: true,
              },
            });

            for (const fieldObj of fieldObjects) {
              if (
                fieldObj.data &&
                "content" in fieldObj.data &&
                fieldObj.data.content?.dataType === "moveObject" &&
                "fields" in fieldObj.data.content
              ) {
                const fieldFields = fieldObj.data.content.fields as Record<
                  string,
                  unknown
                >;
                const key = fieldFields.name as string | undefined;
                const value = fieldFields.value as boolean | undefined;

                if (key && value !== undefined) {
                  freezedMap.set(key, value);
                }
              }
            }
          }

          debugLog(
            "Parsed Operation freezed_operators tableId:%s count:%d",
            tableId,
            freezedMap.size,
          );

          return freezedMap;
        }

        return null;
      } catch (err) {
        errorLog("Error querying Operation object %O", err);

        return null;
      }
    },
    enabled: !!OPERATION_OBJECT_ID,
    staleTime: 30000, // Consider data fresh for 30 seconds
  });

  // Query all OperatorCap objects to get owner using useSuiClientQuery
  const {
    data: operatorCapsRawData,
    isLoading: isLoadingObjects,
    isFetching: isFetchingObjects,
    error: objectsError,
    refetch: refetchObjects,
  } = useSuiClientQuery(
    "multiGetObjects",
    {
      ids: eventsData,
      options: {
        showOwner: true,
        showType: true,
      },
    },
    {
      enabled: eventsData.length > 0,
    },
  );

  // Parse operator caps data
  const operatorCapsData = useMemo(() => {
    if (!operatorCapsRawData) {
      return [];
    }

    const caps: Array<{ objectId: string; owner: string | null }> = [];

    for (const obj of operatorCapsRawData) {
      if (obj.data?.objectId) {
        let owner: string | null = null;

        if (obj.data.owner) {
          if (
            typeof obj.data.owner === "object" &&
            "AddressOwner" in obj.data.owner
          ) {
            owner = obj.data.owner.AddressOwner;
          } else if (
            typeof obj.data.owner === "object" &&
            "ObjectOwner" in obj.data.owner
          ) {
            owner = obj.data.owner.ObjectOwner;
          }
        }

        caps.push({
          objectId: obj.data.objectId,
          owner,
        });
      }
    }

    debugLog("Queried OperatorCap objects count:%d", caps.length);

    return caps;
  }, [operatorCapsRawData]);

  // Combine all data
  const operatorCaps: OperatorCapInfo[] = useMemo(() => {
    if (!eventsData || !operatorCapsData) {
      return [];
    }

    const caps: OperatorCapInfo[] = [];

    for (const capId of eventsData) {
      const capObj = operatorCapsData.find((c) => c.objectId === capId);
      const isFreezed = operationData?.get(capId) ?? false;

      caps.push({
        objectId: capId,
        owner: capObj?.owner || null,
        isFreezed,
      });
    }

    debugLog("Combined OperatorCap info count:%d", caps.length);

    return caps;
  }, [eventsData, operatorCapsData, operationData]);

  return {
    operatorCaps,
    isLoading: isLoadingEvents || isLoadingOperation || isLoadingObjects,
    isFetching: isFetchingEvents || isLoadingOperation || isFetchingObjects,
    error: eventsError || operationError || objectsError,
    pagination: {
      hasNextPage: eventsResult?.hasNextPage || false,
      nextCursor: eventsResult?.nextCursor,
    },
    refetch: () => {
      refetchEvents();
      refetchObjects();
    },
  };
}
