import type { OracleConfig, PriceInfo } from "@/lib/types";

import { useSuiClientQuery } from "@mysten/dapp-kit";
import { useMemo } from "react";

import { loggers } from "@/utils/debug";

const { debugLog, errorLog } = loggers("app:hooks:oracle-config");

const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";

/**
 * Hook to query OracleConfig shared object
 * Returns OracleConfig with all configured aggregators
 */
export function useOracleConfig() {
  // Step 1: Query OracleConfig object
  const {
    data: oracleConfigData,
    isLoading: isLoadingConfig,
    isFetching: isFetchingConfig,
    error: configError,
    refetch: refetchConfig,
  } = useSuiClientQuery(
    "getObject",
    {
      id: VOLO_ORACLE_CONFIG_ID,
      options: {
        showContent: true,
        showType: true,
      },
    },
    {
      enabled: !!VOLO_ORACLE_CONFIG_ID,
      staleTime: 30000, // Consider data fresh for 30 seconds
    },
  );

  // Step 2: Extract aggregators table ID and query dynamic fields
  const aggregatorsTableId = useMemo(() => {
    if (!oracleConfigData?.data) {
      return null;
    }

    if (
      oracleConfigData.data &&
      "content" in oracleConfigData.data &&
      oracleConfigData.data.content?.dataType === "moveObject" &&
      "fields" in oracleConfigData.data.content
    ) {
      const fields = oracleConfigData.data.content.fields as Record<
        string,
        unknown
      >;
      const aggregators = fields.aggregators as
        | {
            fields?: {
              id?: { id?: string };
            };
            id?: { id?: string };
          }
        | undefined;

      const tableId =
        aggregators?.fields?.id?.id ||
        aggregators?.id?.id ||
        (aggregators as { id?: string })?.id;

      return tableId || null;
    }

    return null;
  }, [oracleConfigData]);

  // Step 3: Query dynamic fields of aggregators table
  const {
    data: dynamicFieldsData,
    isLoading: isLoadingFields,
    isFetching: isFetchingFields,
    error: fieldsError,
    refetch: refetchFields,
  } = useSuiClientQuery(
    "getDynamicFields",
    {
      parentId: aggregatorsTableId || "",
      limit: 1000, // Get all aggregators
    },
    {
      enabled: !!aggregatorsTableId,
    },
  );

  // Step 4: Fetch all PriceInfo objects
  const fieldIds = useMemo(
    () => dynamicFieldsData?.data.map((field) => field.objectId) || [],
    [dynamicFieldsData],
  );

  const {
    data: priceInfoObjects,
    isLoading: isLoadingPriceInfos,
    isFetching: isFetchingPriceInfos,
    error: priceInfoError,
    refetch: refetchPriceInfos,
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

  // Parse OracleConfig from query results
  const oracleConfig: OracleConfig | null = useMemo(() => {
    if (!oracleConfigData?.data) {
      return null;
    }

    if (
      oracleConfigData.data &&
      "content" in oracleConfigData.data &&
      oracleConfigData.data.content?.dataType === "moveObject" &&
      "fields" in oracleConfigData.data.content
    ) {
      const fields = oracleConfigData.data.content.fields as Record<
        string,
        unknown
      >;

      const aggregatorsMap = new Map<string, PriceInfo>();

      // Parse PriceInfo from dynamic field objects
      // Dynamic field structure: { name: String, value: PriceInfo }
      if (priceInfoObjects && dynamicFieldsData?.data) {
        priceInfoObjects.forEach((obj, index) => {
          const dynamicField = dynamicFieldsData.data[index];

          if (!dynamicField) {
            return;
          }

          // Extract asset_type from dynamic field name
          // The name can be a string or an object with value property
          let assetType = "";

          if (typeof dynamicField.name === "string") {
            assetType = dynamicField.name;
          } else if (
            dynamicField.name &&
            typeof dynamicField.name === "object"
          ) {
            const nameObj = dynamicField.name as {
              value?: string;
              type?: string;
            };

            assetType = nameObj.value || "";
          }

          if (!assetType) {
            return;
          }

          if (
            obj.data &&
            "content" in obj.data &&
            obj.data.content?.dataType === "moveObject" &&
            "fields" in obj.data.content
          ) {
            const dynamicFieldContent = obj.data.content.fields as Record<
              string,
              unknown
            >;

            // The dynamic field structure is: { name: String, value: PriceInfo }
            // Extract PriceInfo from value field
            const value = dynamicFieldContent.value as
              | {
                  fields?: Record<string, unknown>;
                }
              | Record<string, unknown>
              | undefined;

            const priceInfoFields =
              (value?.fields as Record<string, unknown>) || value || {};

            const priceInfo: PriceInfo = {
              aggregator: String(priceInfoFields.aggregator || ""),
              decimals: Number(priceInfoFields.decimals || 0),
              price: String(priceInfoFields.price || "0"),
              last_updated: Number(priceInfoFields.last_updated || 0),
            };

            aggregatorsMap.set(assetType, priceInfo);
          }
        });
      }

      return {
        id: VOLO_ORACLE_CONFIG_ID,
        version: Number(fields.version || 0),
        update_interval: Number(fields.update_interval || 0),
        dex_slippage: String(fields.dex_slippage || "0"),
        aggregators: aggregatorsMap,
      };
    }

    return null;
  }, [oracleConfigData, priceInfoObjects, dynamicFieldsData]);

  const isLoading = isLoadingConfig || isLoadingFields || isLoadingPriceInfos;
  const isFetching =
    isFetchingConfig || isFetchingFields || isFetchingPriceInfos;
  const error = configError || fieldsError || priceInfoError;

  if (error) {
    errorLog("Error querying OracleConfig %O", error);
  }

  const refetch = () => {
    refetchConfig();
    refetchFields();
    refetchPriceInfos();
  };

  debugLog(
    "OracleConfig query isLoading:%s aggregatorsCount:%d",
    isLoading,
    oracleConfig?.aggregators.size || 0,
  );

  return {
    oracleConfig,
    isLoading,
    isFetching,
    error,
    refetch,
  };
}
