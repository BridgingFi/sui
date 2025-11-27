import {
  Alert,
  Button,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Spinner,
} from "@heroui/react";
import { useState, useEffect, useMemo } from "react";
import { useSuiClientQuery } from "@mysten/dapp-kit";
import dayjs from "dayjs";

import { SwitchboardAggregatorBrowser } from "./SwitchboardAggregatorBrowser";

import { useOracleConfig } from "@/hooks/useOracleConfig";
import { loggers } from "@/utils/debug";

const { errorLog } = loggers("app:manage:add-aggregator-modal");

interface AggregatorCheckStatus {
  isValid: boolean;
  message: string;
  isLoading: boolean;
  timestamp?: number;
  timeDiff?: number;
}

interface AddAggregatorModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAdd: (
    assetType: string,
    decimals: number,
    aggregatorId: string,
  ) => Promise<void>;
  isAdding: boolean;
}

export function AddAggregatorModal({
  isOpen,
  onClose,
  onAdd,
  isAdding,
}: AddAggregatorModalProps) {
  const { oracleConfig } = useOracleConfig();
  const [assetType, setAssetType] = useState("");
  const [decimals, setDecimals] = useState("6");
  const [aggregatorId, setAggregatorId] = useState("");
  const [aggregatorCheckStatus, setAggregatorCheckStatus] =
    useState<AggregatorCheckStatus | null>(null);

  // Normalize assetType for RPC call (keep 0x prefix for getCoinMetadata)
  const normalizedAssetTypeForRPC = useMemo(() => {
    const trimmed = assetType.trim();

    if (!trimmed || !trimmed.includes("::")) {
      return null;
    }

    // getCoinMetadata accepts format with 0x prefix
    // If user input doesn't have 0x, add it
    if (!trimmed.startsWith("0x")) {
      return `0x${trimmed}`;
    }

    return trimmed;
  }, [assetType]);

  // Auto-fetch coin decimals using useSuiClientQuery
  const {
    data: coinMetadata,
    isLoading: isLoadingDecimals,
    error: decimalsError,
  } = useSuiClientQuery(
    "getCoinMetadata",
    {
      coinType: normalizedAssetTypeForRPC || "",
    },
    {
      enabled: !!normalizedAssetTypeForRPC,
      // Don't refetch if we already have decimals set
      staleTime: Infinity,
    },
  );

  // Update decimals when metadata is fetched
  useEffect(() => {
    if (coinMetadata?.decimals !== undefined) {
      setDecimals(coinMetadata.decimals.toString());
      errorLog(
        "Auto-fetched decimals for %s: %d",
        normalizedAssetTypeForRPC,
        coinMetadata.decimals,
      );
    }
  }, [coinMetadata, normalizedAssetTypeForRPC]);

  // Reset form when modal closes
  useEffect(() => {
    if (!isOpen) {
      setAssetType("");
      setDecimals("18");
      setAggregatorId("");
      setAggregatorCheckStatus(null);
    }
  }, [isOpen]);

  // Query aggregator object using useSuiClientQuery
  const trimmedAggregatorId = aggregatorId.trim();
  const {
    data: aggregatorData,
    isLoading: isLoadingAggregator,
    error: aggregatorError,
  } = useSuiClientQuery(
    "getObject",
    {
      id: trimmedAggregatorId,
      options: {
        showContent: true,
      },
    },
    {
      enabled: !!trimmedAggregatorId && !!oracleConfig,
      // Debounce by using staleTime and refetchInterval
      staleTime: 500,
    },
  );

  // Check aggregator price update status when aggregator data changes
  useEffect(() => {
    if (!aggregatorId.trim() || !oracleConfig) {
      setAggregatorCheckStatus(null);

      return;
    }

    if (isLoadingAggregator) {
      setAggregatorCheckStatus({
        isValid: false,
        message: "",
        isLoading: true,
      });

      return;
    }

    if (aggregatorError) {
      errorLog("Error checking aggregator status: %O", aggregatorError);
      setAggregatorCheckStatus({
        isValid: false,
        message:
          aggregatorError instanceof Error
            ? aggregatorError.message
            : "Failed to check aggregator",
        isLoading: false,
      });

      return;
    }

    if (!aggregatorData?.data) {
      setAggregatorCheckStatus({
        isValid: false,
        message: "Aggregator not found",
        isLoading: false,
      });

      return;
    }

    if (
      aggregatorData.data &&
      "content" in aggregatorData.data &&
      aggregatorData.data.content?.dataType === "moveObject" &&
      "fields" in aggregatorData.data.content
    ) {
      const fields = aggregatorData.data.content.fields as Record<
        string,
        unknown
      >;

      // Extract current_result.max_timestamp_ms
      const currentResult = fields.current_result as
        | {
            fields?: {
              max_timestamp_ms?: string | number;
            };
            max_timestamp_ms?: string | number;
          }
        | undefined;

      const maxTimestampMs =
        currentResult?.fields?.max_timestamp_ms ||
        currentResult?.max_timestamp_ms ||
        (currentResult as { max_timestamp_ms?: string | number })
          ?.max_timestamp_ms;

      if (!maxTimestampMs) {
        setAggregatorCheckStatus({
          isValid: false,
          message: "Cannot read aggregator timestamp",
          isLoading: false,
        });

        return;
      }

      const maxTimestamp = Number(maxTimestampMs);
      const now = Date.now();
      const updateInterval = oracleConfig.update_interval;
      const timeDiff = now - maxTimestamp;

      // Check: if now >= max_timestamp, then now - max_timestamp < update_interval
      if (now >= maxTimestamp) {
        if (timeDiff < updateInterval) {
          const remainingMs = updateInterval - timeDiff;
          const remainingSec = Math.floor(remainingMs / 1000);

          setAggregatorCheckStatus({
            isValid: true,
            message: `Price is fresh (updated ${remainingSec}s ago, valid for ${Math.floor(updateInterval / 1000)}s)`,
            isLoading: false,
            timestamp: maxTimestamp,
            timeDiff,
          });
        } else {
          const staleSec = Math.floor(timeDiff / 1000);

          setAggregatorCheckStatus({
            isValid: false,
            message: `Price is stale (updated ${staleSec}s ago, exceeds ${Math.floor(updateInterval / 1000)}s limit)`,
            isLoading: false,
            timestamp: maxTimestamp,
            timeDiff,
          });
        }
      } else {
        // now < max_timestamp (shouldn't happen, but handle it)
        setAggregatorCheckStatus({
          isValid: true,
          message: "Price timestamp is in the future",
          isLoading: false,
          timestamp: maxTimestamp,
          timeDiff: maxTimestamp - now,
        });
      }
    } else {
      setAggregatorCheckStatus({
        isValid: false,
        message: "Invalid aggregator object format",
        isLoading: false,
      });
    }
  }, [
    aggregatorId,
    aggregatorData,
    aggregatorError,
    isLoadingAggregator,
    oracleConfig,
  ]);

  const handleAdd = async () => {
    if (!assetType.trim() || !decimals || !aggregatorId.trim()) {
      return;
    }

    await onAdd(assetType.trim(), parseInt(decimals, 10), aggregatorId.trim());
  };

  return (
    <Modal isOpen={isOpen} size="2xl" onClose={onClose}>
      <ModalContent>
        <ModalHeader>Add Aggregator</ModalHeader>
        <ModalBody>
          <div className="space-y-4">
            <Input
              description="Full type tag of the asset"
              label="Asset Type"
              placeholder="e.g., 0x2::sui::SUI or 2::sui::SUI"
              value={assetType}
              onValueChange={setAssetType}
            />
            <Input
              color={decimalsError ? "warning" : undefined}
              description={
                isLoadingDecimals
                  ? "Fetching decimals from chain..."
                  : decimalsError
                    ? `Error: ${decimalsError.message || "Failed to fetch decimals"}. Please enter manually.`
                    : coinMetadata
                      ? `Auto-fetched: ${coinMetadata.decimals} decimals`
                      : "Number of decimals (will auto-fetch if asset type is valid)"
              }
              endContent={isLoadingDecimals ? <Spinner size="sm" /> : null}
              isDisabled={isLoadingDecimals}
              label="Decimals"
              type="number"
              value={decimals}
              variant={decimalsError ? "bordered" : undefined}
              onValueChange={setDecimals}
            />
            <Input
              description="Switchboard Aggregator object ID"
              label="Aggregator ID"
              placeholder="0x..."
              value={aggregatorId}
              onValueChange={setAggregatorId}
            />
            {aggregatorCheckStatus && (
              <Alert
                color={aggregatorCheckStatus.isValid ? "success" : "warning"}
                variant="flat"
              >
                {aggregatorCheckStatus.isLoading ? (
                  <div className="flex items-center gap-2">
                    <Spinner size="sm" />
                    <span>Checking aggregator status...</span>
                  </div>
                ) : (
                  <div className="space-y-1">
                    <div>{aggregatorCheckStatus.message}</div>
                    {aggregatorCheckStatus.timestamp !== undefined && (
                      <div className="text-xs opacity-80">
                        Timestamp: {aggregatorCheckStatus.timestamp} (
                        {dayjs(aggregatorCheckStatus.timestamp).format(
                          "YYYY-MM-DD HH:mm:ss",
                        )}
                        )
                        {aggregatorCheckStatus.timeDiff !== undefined && (
                          <>
                            {" "}
                            | Time diff:{" "}
                            {Math.floor(aggregatorCheckStatus.timeDiff / 1000)}s
                          </>
                        )}
                      </div>
                    )}
                  </div>
                )}
              </Alert>
            )}
            <div className="pt-4">
              <SwitchboardAggregatorBrowser
                onSelect={(id) => {
                  setAggregatorId(id);
                }}
              />
            </div>
          </div>
        </ModalBody>
        <ModalFooter>
          <Button variant="light" onPress={onClose}>
            Cancel
          </Button>
          <Button
            color="primary"
            isDisabled={!assetType.trim() || !decimals || !aggregatorId.trim()}
            isLoading={isAdding}
            onPress={handleAdd}
          >
            Add
          </Button>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
