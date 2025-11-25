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
import { useState, useEffect } from "react";
import { useSuiClient } from "@mysten/dapp-kit";
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
  const client = useSuiClient();
  const [assetType, setAssetType] = useState("");
  const [decimals, setDecimals] = useState("18");
  const [aggregatorId, setAggregatorId] = useState("");
  const [aggregatorCheckStatus, setAggregatorCheckStatus] =
    useState<AggregatorCheckStatus | null>(null);

  // Reset form when modal closes
  useEffect(() => {
    if (!isOpen) {
      setAssetType("");
      setDecimals("18");
      setAggregatorId("");
      setAggregatorCheckStatus(null);
    }
  }, [isOpen]);

  // Check aggregator price update status when aggregatorId changes
  useEffect(() => {
    const checkAggregatorStatus = async () => {
      if (!aggregatorId.trim() || !oracleConfig) {
        setAggregatorCheckStatus(null);

        return;
      }

      setAggregatorCheckStatus({
        isValid: false,
        message: "",
        isLoading: true,
      });

      try {
        // Query aggregator object
        const aggregatorData = await client.getObject({
          id: aggregatorId.trim(),
          options: {
            showContent: true,
          },
        });

        if (!aggregatorData.data) {
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
      } catch (err) {
        errorLog("Error checking aggregator status: %O", err);
        setAggregatorCheckStatus({
          isValid: false,
          message:
            err instanceof Error ? err.message : "Failed to check aggregator",
          isLoading: false,
        });
      }
    };

    // Debounce the check
    const timeoutId = setTimeout(() => {
      checkAggregatorStatus();
    }, 500);

    return () => clearTimeout(timeoutId);
  }, [aggregatorId, oracleConfig, client]);

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
              placeholder="e.g., 0x2::sui::SUI"
              value={assetType}
              onValueChange={setAssetType}
            />
            <Input
              description="Number of decimals (typically 18)"
              label="Decimals"
              type="number"
              value={decimals}
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
