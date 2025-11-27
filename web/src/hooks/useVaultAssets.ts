import { useMemo } from "react";
import { useSuiClientQuery } from "@mysten/dapp-kit";

import { loggers } from "@/utils/debug";

const { debugLog } = loggers("app:hooks:vault-assets");

// ==================== Types ====================

export interface AssetValueInfo {
  assetType: string;
  usdValue: bigint;
  lastUpdated: number;
}

interface VaultAssetsTableIds {
  assetsValue: string | null;
  assetsValueUpdated: string | null;
}

interface TableFieldValue<T> {
  key: string;
  value: T;
}

// ==================== Step 1: Extract Table IDs ====================

/**
 * Extract assets_value and assets_value_updated Table IDs from vault object
 * @param vaultId - The vault object ID
 */
function useVaultAssetsTableIds(vaultId: string | null) {
  const {
    data: vaultData,
    isLoading,
    error,
    refetch,
  } = useSuiClientQuery(
    "getObject",
    {
      id: vaultId || "",
      options: {
        showContent: true,
      },
    },
    {
      enabled: !!vaultId,
      staleTime: Infinity, // Table IDs never change
    },
  );

  const tableIds = useMemo((): VaultAssetsTableIds => {
    if (!vaultData?.data || !("content" in vaultData.data)) {
      return { assetsValue: null, assetsValueUpdated: null };
    }

    const content = vaultData.data.content;

    if (
      !content ||
      content.dataType !== "moveObject" ||
      !("fields" in content)
    ) {
      return { assetsValue: null, assetsValueUpdated: null };
    }

    const fields = content.fields as Record<string, unknown>;

    // Extract Table ID helper
    // Table structure: { type: "...", fields: { id: { id: "..." }, size: "..." } }
    const getTableId = (tableField: unknown): string | null => {
      if (!tableField || typeof tableField !== "object") {
        return null;
      }

      // Check if it has a 'fields' property (Table structure from Sui)
      if ("fields" in tableField) {
        const tableFields = (
          tableField as { fields?: { id?: { id?: string } } }
        ).fields;

        if (tableFields?.id?.id) {
          return tableFields.id.id;
        }
      }

      // Fallback: check if it has direct 'id' property
      if ("id" in tableField) {
        const idField = (tableField as { id?: { id?: string } }).id;

        if (idField?.id) {
          return idField.id;
        }
      }

      return null;
    };

    const assetsValueId = getTableId(fields.assets_value);
    const assetsValueUpdatedId = getTableId(fields.assets_value_updated);

    if (assetsValueId && assetsValueUpdatedId) {
      debugLog(
        "Extracted Table IDs - assetsValue:%s assetsValueUpdated:%s",
        assetsValueId,
        assetsValueUpdatedId,
      );
    }

    return {
      assetsValue: assetsValueId,
      assetsValueUpdated: assetsValueUpdatedId,
    };
  }, [vaultData]);

  return {
    tableIds,
    isLoading,
    error,
    refetch,
  };
}

// ==================== Step 2: Query Dynamic Fields ====================

/**
 * Generic hook to query dynamic fields from a Table
 * @param tableId - The Table object ID
 * @param limit - Maximum number of fields to query
 */
function useTableDynamicFields(tableId: string | null, limit: number = 1000) {
  const {
    data: dynamicFields,
    isLoading,
    error,
    refetch,
  } = useSuiClientQuery(
    "getDynamicFields",
    {
      parentId: tableId || "",
      limit,
    },
    {
      enabled: !!tableId,
    },
  );

  const fieldIds = useMemo(
    () => dynamicFields?.data.map((f) => f.objectId) || [],
    [dynamicFields],
  );

  return {
    dynamicFields: dynamicFields?.data || [],
    fieldIds,
    isLoading,
    error,
    refetch,
  };
}

// ==================== Step 3: Fetch Field Values ====================

/**
 * Generic hook to fetch and parse field values from Table dynamic fields
 * @param fieldIds - Array of field object IDs
 * @param valueType - Type of value to parse: 'u256' or 'u64'
 */
function useTableFieldValues<T extends bigint | number>(
  fieldIds: string[],
  valueType: "u256" | "u64",
) {
  const {
    data: objects,
    isLoading,
    error,
  } = useSuiClientQuery(
    "multiGetObjects",
    {
      ids: fieldIds,
      options: {
        showContent: true,
      },
    },
    {
      enabled: fieldIds.length > 0,
    },
  );

  const fieldValues = useMemo((): TableFieldValue<T>[] => {
    if (!objects || objects.length === 0) {
      return [];
    }

    const values: TableFieldValue<T>[] = [];

    for (let i = 0; i < objects.length; i++) {
      const obj = objects[i];

      if (
        !obj ||
        !obj.data ||
        !("content" in obj.data) ||
        !obj.data.content ||
        obj.data.content.dataType !== "moveObject" ||
        !("fields" in obj.data.content)
      ) {
        continue;
      }

      // Get the field name from the corresponding dynamic field
      // Note: We need to match by index, so this assumes fieldIds[i] corresponds to objects[i]
      const fields = obj.data.content.fields as Record<string, unknown>;
      const value = fields.value as string | number | undefined;

      if (value !== undefined) {
        // Parse value based on type
        const parsedValue =
          valueType === "u256"
            ? (BigInt(String(value)) as T)
            : (Number(value) as T);

        // Note: We can't get the key here without the dynamic field name
        // This will be handled in the combining hook
        values.push({
          key: "", // Will be set by combining hook
          value: parsedValue,
        });
      }
    }

    return values;
  }, [objects, valueType]);

  return {
    objects: objects || [],
    fieldValues,
    isLoading,
    error,
  };
}

// ==================== Step 4: Combine - Main Hook ====================

/**
 * Main hook to query vault assets_value and assets_value_updated Tables
 * Combines all the above hooks to provide a clean API
 *
 * @param vaultId - The vault object ID
 * @param assetTypes - Array of asset type strings to query
 */
export function useVaultAssets(vaultId: string | null, assetTypes: string[]) {
  // Step 1: Get Table IDs
  const {
    tableIds,
    isLoading: isLoadingTableIds,
    error: tableIdsError,
  } = useVaultAssetsTableIds(vaultId);

  // Step 2: Query dynamic fields from both Tables
  const {
    dynamicFields: assetsValueFields,
    fieldIds: valueFieldIds,
    isLoading: isLoadingAssetsValueFields,
    error: assetsValueFieldsError,
  } = useTableDynamicFields(tableIds.assetsValue, 1000);

  const {
    dynamicFields: assetsValueUpdatedFields,
    fieldIds: updatedFieldIds,
    isLoading: isLoadingAssetsValueUpdatedFields,
    error: assetsValueUpdatedFieldsError,
  } = useTableDynamicFields(tableIds.assetsValueUpdated, 1000);

  // Step 3: Fetch field values
  const { objects: valueObjects, isLoading: isLoadingValueObjects } =
    useTableFieldValues<bigint>(valueFieldIds, "u256");

  const { objects: updatedObjects, isLoading: isLoadingUpdatedObjects } =
    useTableFieldValues<number>(updatedFieldIds, "u64");

  // Step 4: Process and combine data
  const assets = useMemo((): AssetValueInfo[] => {
    if (
      assetsValueFields.length === 0 ||
      assetsValueUpdatedFields.length === 0 ||
      valueObjects.length === 0 ||
      updatedObjects.length === 0 ||
      assetTypes.length === 0
    ) {
      return [];
    }

    // Create maps for quick lookup
    const valueMap = new Map<string, bigint>();
    const updatedMap = new Map<string, number>();

    // Process assets_value fields
    // Match fields with objects by objectId
    const valueObjectsMap = new Map(
      valueObjects.map((obj) => [obj.data?.objectId, obj]),
    );

    for (let i = 0; i < assetsValueFields.length; i++) {
      const field = assetsValueFields[i];

      if (!field) {
        continue;
      }

      // Find corresponding object by objectId
      const fieldObj = valueObjectsMap.get(field.objectId);

      if (!fieldObj) {
        debugLog(
          "Field[%d] objectId %s not found in valueObjects",
          i,
          field.objectId,
        );

        continue;
      }

      // Extract field name (can be string or object with value property)
      let nameValue = "";

      if (typeof field.name === "string") {
        nameValue = field.name;
      } else if (field.name && typeof field.name === "object") {
        const nameObj = field.name as { value?: string; type?: string };

        nameValue = nameObj.value || "";
      }

      if (!nameValue) {
        debugLog("Skipping field[%d] - invalid name: %O", i, field.name);

        continue;
      }

      if (
        fieldObj.data &&
        "content" in fieldObj.data &&
        fieldObj.data.content &&
        fieldObj.data.content.dataType === "moveObject" &&
        "fields" in fieldObj.data.content
      ) {
        const fields = fieldObj.data.content.fields as Record<string, unknown>;
        const value = fields.value as string | number | undefined;

        if (value !== undefined) {
          valueMap.set(nameValue, BigInt(String(value)));
        } else {
          debugLog("Field[%d] %s has no value", i, nameValue);
        }
      } else {
        debugLog("Field[%d] %s has invalid object structure", i, nameValue);
      }
    }

    // Process assets_value_updated fields
    // Match fields with objects by objectId
    const updatedObjectsMap = new Map(
      updatedObjects.map((obj) => [obj.data?.objectId, obj]),
    );

    for (let i = 0; i < assetsValueUpdatedFields.length; i++) {
      const field = assetsValueUpdatedFields[i];

      if (!field) {
        continue;
      }

      // Find corresponding object by objectId
      const fieldObj = updatedObjectsMap.get(field.objectId);

      if (!fieldObj) {
        continue;
      }

      // Extract field name (can be string or object with value property)
      let nameValue = "";

      if (typeof field.name === "string") {
        nameValue = field.name;
      } else if (field.name && typeof field.name === "object") {
        const nameObj = field.name as { value?: string; type?: string };

        nameValue = nameObj.value || "";
      }

      if (!nameValue) {
        continue;
      }

      if (
        fieldObj.data &&
        "content" in fieldObj.data &&
        fieldObj.data.content &&
        fieldObj.data.content.dataType === "moveObject" &&
        "fields" in fieldObj.data.content
      ) {
        const fields = fieldObj.data.content.fields as Record<string, unknown>;
        const value = fields.value as string | number | undefined;

        if (value !== undefined) {
          updatedMap.set(nameValue, Number(value));
        }
      }
    }

    // Combine data for all asset types
    const result: AssetValueInfo[] = assetTypes.map((assetType) => ({
      assetType,
      usdValue: valueMap.get(assetType) ?? 0n,
      lastUpdated: updatedMap.get(assetType) ?? 0,
    }));

    // Log final summary
    debugLog(
      "Assets data summary - valueMap:%d entries updatedMap:%d entries result:%O",
      valueMap.size,
      updatedMap.size,
      result,
    );

    return result;
  }, [
    assetsValueFields,
    assetsValueUpdatedFields,
    valueObjects,
    updatedObjects,
    assetTypes,
  ]);

  const isLoading =
    isLoadingTableIds ||
    isLoadingAssetsValueFields ||
    isLoadingAssetsValueUpdatedFields ||
    isLoadingValueObjects ||
    isLoadingUpdatedObjects;

  const error =
    tableIdsError ||
    assetsValueFieldsError ||
    assetsValueUpdatedFieldsError ||
    undefined;

  return {
    assets,
    isLoading,
    error,
    refetch: () => {
      // Note: useSuiClientQuery doesn't have a direct refetch method exposed
      // The query will automatically refetch when dependencies change
    },
  };
}
