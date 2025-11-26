import {
  addToast,
  Alert,
  Button,
  Card,
  CardBody,
  CardHeader,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Popover,
  PopoverContent,
  PopoverTrigger,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
} from "@heroui/react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { Copy, Edit, InfoCircle, Plus, Refresh, Trash } from "iconoir-react";
import { useState } from "react";
import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";

dayjs.extend(duration);

import { AddAggregatorModal } from "./AddAggregatorModal";
import { SwitchboardAggregatorBrowser } from "./SwitchboardAggregatorBrowser";

import { useOracleConfig } from "@/hooks/useOracleConfig";
import { useAdminCap } from "@/hooks/useAdminCap";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";

const { errorLog } = loggers("app:manage:oracle-config");

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";
const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

function truncateAssetType(assetType: string): string {
  if (assetType.length <= 30) {
    return assetType;
  }

  return `${assetType.slice(0, 20)}...${assetType.slice(-10)}`;
}

/**
 * Format duration in milliseconds to human readable format
 * @param ms - Duration in milliseconds
 * @returns Human readable duration string (e.g., "1 minute", "2 hours", "30 seconds")
 */
function formatDuration(ms: number): string {
  const duration = dayjs.duration(ms);

  return duration.humanize();
}

function formatValue(value: string, decimals: number): string {
  try {
    const bigIntValue = BigInt(value);
    const divisor = BigInt(10 ** decimals);
    const quotient = bigIntValue / divisor;
    const remainder = bigIntValue % divisor;

    if (remainder === BigInt(0)) {
      return quotient.toString();
    }

    const decimalPart = remainder.toString().padStart(decimals, "0");
    const trimmedDecimal = decimalPart.replace(/0+$/, "");

    return `${quotient}.${trimmedDecimal}`;
  } catch {
    return value;
  }
}

function formatTimestamp(timestampMs: number): string {
  try {
    const date = new Date(timestampMs);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffSeconds = Math.floor(diffMs / 1000);
    const diffMinutes = Math.floor(diffSeconds / 60);
    const diffHours = Math.floor(diffMinutes / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffDays > 0) {
      return `${diffDays} day${diffDays > 1 ? "s" : ""} ago`;
    }
    if (diffHours > 0) {
      return `${diffHours} hour${diffHours > 1 ? "s" : ""} ago`;
    }
    if (diffMinutes > 0) {
      return `${diffMinutes} minute${diffMinutes > 1 ? "s" : ""} ago`;
    }
    if (diffSeconds > 0) {
      return `${diffSeconds} second${diffSeconds > 1 ? "s" : ""} ago`;
    }

    return "Just now";
  } catch {
    return "Unknown";
  }
}

function copyToClipboard(text: string) {
  navigator.clipboard.writeText(text);
  addToast({
    title: "Copied",
    description: "Copied to clipboard",
    color: "success",
  });
}

/**
 * OracleConfig management component
 * Displays OracleConfig state and allows AdminCap holders to manage aggregators
 */
export function OracleConfigDetail() {
  const { oracleConfig, isLoading, isFetching, refetch } = useOracleConfig();
  const { adminCap, hasAdminCap } = useAdminCap();
  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecute } = useSignAndExecuteTransaction();
  const client = useSuiClient();

  // Add aggregator modal state
  const [isAddModalOpen, setIsAddModalOpen] = useState(false);
  const [isAdding, setIsAdding] = useState(false);

  // Edit config modal state
  const [isEditConfigModalOpen, setIsEditConfigModalOpen] = useState(false);
  const [updateInterval, setUpdateInterval] = useState("");
  const [dexSlippage, setDexSlippage] = useState("");
  const [isEditingConfig, setIsEditingConfig] = useState(false);

  // Change aggregator modal state
  const [changingAssetType, setChangingAssetType] = useState<string | null>(
    null,
  );
  const [newAggregatorId, setNewAggregatorId] = useState("");
  const [isChanging, setIsChanging] = useState(false);

  // Remove aggregator state
  const [removingAssetType, setRemovingAssetType] = useState<string | null>(
    null,
  );
  const [isRemoving, setIsRemoving] = useState(false);

  const handleAddAggregator = async (
    assetType: string,
    decimals: number,
    aggregatorId: string,
  ) => {
    if (!currentAccount || !adminCap) {
      addToast({
        title: "Permission denied",
        description: "AdminCap required",
        color: "danger",
      });

      return;
    }

    if (!assetType.trim() || !decimals || !aggregatorId.trim()) {
      addToast({
        title: "Invalid input",
        description: "Please fill all fields",
        color: "danger",
      });

      return;
    }

    setIsAdding(true);

    try {
      const tx = new Transaction();

      // Normalize assetType: remove 0x prefix if present
      // type_name::get<CoinType>().into_string() produces format without 0x prefix
      // e.g., "ea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC"
      // not "0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC"
      let normalizedAssetType = assetType.trim();

      // Remove 0x prefix if the address part starts with 0x
      // Pattern: 0x<address>::<module>::<name> -> <address>::<module>::<name>
      if (normalizedAssetType.startsWith("0x")) {
        // Find the first :: to determine where the address ends
        const firstColonIndex = normalizedAssetType.indexOf("::");

        if (firstColonIndex > 2) {
          // Remove 0x prefix from address part only
          // 0x<address>::module::name -> <address>::module::name
          normalizedAssetType =
            normalizedAssetType.substring(2, firstColonIndex) +
            normalizedAssetType.substring(firstColonIndex);
        } else {
          // If no :: found, just remove 0x prefix
          normalizedAssetType = normalizedAssetType.substring(2);
        }
      }

      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID}::vault_manage::add_switchboard_aggregator`,
        arguments: [
          tx.object(adminCap.objectId),
          tx.object(VOLO_ORACLE_CONFIG_ID),
          tx.object(SUI_CLOCK_OBJECT_ID),
          tx.pure.string(normalizedAssetType),
          tx.pure.u8(decimals),
          tx.object(aggregatorId),
        ],
      });

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setIsAdding(false);
            setIsAddModalOpen(false);
            addToast({
              title: "Success",
              description: "Aggregator added successfully",
              color: "success",
            });
            setTimeout(() => {
              refetch();
            }, 2000);
          },
          onError: (err) => {
            setIsAdding(false);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Add aggregator failed",
            );
          },
        },
      );
    } catch (err) {
      setIsAdding(false);
      errorLog("Add aggregator error: %O", err);
      addToast({
        title: "Error",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
    }
  };

  const handleRemoveAggregator = async (assetTypeToRemove: string) => {
    if (!currentAccount || !adminCap) {
      addToast({
        title: "Permission denied",
        description: "AdminCap required",
        color: "danger",
      });

      return;
    }

    setIsRemoving(true);
    setRemovingAssetType(assetTypeToRemove);

    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID}::vault_manage::remove_switchboard_aggregator`,
        arguments: [
          tx.object(adminCap.objectId),
          tx.object(VOLO_ORACLE_CONFIG_ID),
          tx.pure.string(assetTypeToRemove),
        ],
      });

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setIsRemoving(false);
            setRemovingAssetType(null);
            addToast({
              title: "Success",
              description: "Aggregator removed successfully",
              color: "success",
            });
            setTimeout(() => {
              refetch();
            }, 2000);
          },
          onError: (err) => {
            setIsRemoving(false);
            setRemovingAssetType(null);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Remove aggregator failed",
            );
          },
        },
      );
    } catch (err) {
      setIsRemoving(false);
      setRemovingAssetType(null);
      errorLog("Remove aggregator error: %O", err);
      addToast({
        title: "Error",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
    }
  };

  const handleChangeAggregator = async () => {
    if (!currentAccount || !adminCap || !changingAssetType) {
      addToast({
        title: "Permission denied",
        description: "AdminCap required",
        color: "danger",
      });

      return;
    }

    if (!newAggregatorId.trim()) {
      addToast({
        title: "Invalid input",
        description: "Please enter aggregator ID",
        color: "danger",
      });

      return;
    }

    setIsChanging(true);

    try {
      const tx = new Transaction();

      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID}::vault_manage::change_switchboard_aggregator`,
        arguments: [
          tx.object(adminCap.objectId),
          tx.object(VOLO_ORACLE_CONFIG_ID),
          tx.object(SUI_CLOCK_OBJECT_ID),
          tx.pure.string(changingAssetType),
          tx.object(newAggregatorId.trim()),
        ],
      });

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setIsChanging(false);
            setChangingAssetType(null);
            setNewAggregatorId("");
            addToast({
              title: "Success",
              description: "Aggregator changed successfully",
              color: "success",
            });
            setTimeout(() => {
              refetch();
            }, 2000);
          },
          onError: (err) => {
            setIsChanging(false);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Change aggregator failed",
            );
          },
        },
      );
    } catch (err) {
      setIsChanging(false);
      errorLog("Change aggregator error: %O", err);
      addToast({
        title: "Error",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
    }
  };

  const handleUpdateConfig = async () => {
    if (!currentAccount || !adminCap) {
      addToast({
        title: "Permission denied",
        description: "AdminCap required",
        color: "danger",
      });

      return;
    }

    setIsEditingConfig(true);

    try {
      const tx = new Transaction();

      if (updateInterval) {
        tx.moveCall({
          target: `${VOLO_VAULT_PACKAGE_ID}::vault_manage::set_update_interval`,
          arguments: [
            tx.object(adminCap.objectId),
            tx.object(VOLO_ORACLE_CONFIG_ID),
            tx.pure.u64(parseInt(updateInterval, 10)),
          ],
        });
      }

      if (dexSlippage) {
        tx.moveCall({
          target: `${VOLO_VAULT_PACKAGE_ID}::vault_manage::set_dex_slippage`,
          arguments: [
            tx.object(adminCap.objectId),
            tx.object(VOLO_ORACLE_CONFIG_ID),
            tx.pure.u256(dexSlippage),
          ],
        });
      }

      if (!updateInterval && !dexSlippage) {
        addToast({
          title: "Invalid input",
          description: "Please enter at least one value",
          color: "danger",
        });
        setIsEditingConfig(false);

        return;
      }

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setIsEditingConfig(false);
            setIsEditConfigModalOpen(false);
            setUpdateInterval("");
            setDexSlippage("");
            addToast({
              title: "Success",
              description: "Configuration updated successfully",
              color: "success",
            });
            setTimeout(() => {
              refetch();
            }, 2000);
          },
          onError: (err) => {
            setIsEditingConfig(false);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Update config failed",
            );
          },
        },
      );
    } catch (err) {
      setIsEditingConfig(false);
      errorLog("Update config error: %O", err);
      addToast({
        title: "Error",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Spinner size="lg" />
      </div>
    );
  }

  if (!oracleConfig) {
    return (
      <Alert color="danger">
        Failed to load OracleConfig. Please check configuration.
      </Alert>
    );
  }

  const aggregatorsArray = Array.from(oracleConfig.aggregators.entries());

  return (
    <div className="space-y-6">
      {!hasAdminCap && (
        <Alert color="warning">
          View-only mode. AdminCap required to modify settings.
        </Alert>
      )}

      {/* Configuration Overview */}
      <Card>
        <CardHeader>
          <div className="flex w-full items-center justify-between">
            <h2 className="text-lg font-semibold">Configuration</h2>
            {hasAdminCap && (
              <Button
                size="sm"
                startContent={<Edit className="w-4 h-4" />}
                variant="flat"
                onPress={() => {
                  setUpdateInterval("");
                  setDexSlippage("");
                  setIsEditConfigModalOpen(true);
                }}
              >
                Edit
              </Button>
            )}
          </div>
        </CardHeader>
        <CardBody>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <div className="text-sm text-default-500">Update Interval</div>
              <div className="text-lg font-semibold">
                {formatDuration(oracleConfig.update_interval)}
              </div>
              <div className="text-sm text-default-500">
                Used to check if the price or usd value is updated within the
                interval
              </div>
            </div>
            <div>
              <div className="text-sm text-default-500">DEX Slippage</div>
              <div className="text-lg font-semibold">
                {((Number(oracleConfig.dex_slippage) / 1e9) * 100).toFixed(2)}%
              </div>
            </div>
          </div>
        </CardBody>
      </Card>

      {/* Configured Aggregators */}
      <Card>
        <CardHeader>
          <div className="flex w-full items-center justify-between">
            <h2 className="text-lg font-semibold">Configured Aggregators</h2>
            <div className="flex gap-2">
              <Button
                isIconOnly
                isLoading={isFetching}
                size="sm"
                variant="light"
                onPress={() => refetch()}
              >
                <Refresh className="w-4 h-4" />
              </Button>
              {hasAdminCap && (
                <Button
                  color="primary"
                  size="sm"
                  startContent={<Plus className="w-4 h-4" />}
                  onPress={() => setIsAddModalOpen(true)}
                >
                  Add Aggregator
                </Button>
              )}
            </div>
          </div>
        </CardHeader>
        <CardBody>
          {aggregatorsArray.length === 0 ? (
            <div className="py-8 text-center text-default-500">
              No aggregators configured
            </div>
          ) : (
            <Table aria-label="Configured Aggregators">
              <TableHeader>
                <TableColumn>Asset Type</TableColumn>
                <TableColumn>Aggregator Address</TableColumn>
                <TableColumn>Decimals</TableColumn>
                <TableColumn>Current Price</TableColumn>
                <TableColumn>Last Updated</TableColumn>
                <TableColumn>Actions</TableColumn>
              </TableHeader>
              <TableBody>
                {aggregatorsArray.map(([assetType, priceInfo]) => (
                  <TableRow key={assetType}>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <span>{truncateAssetType(assetType)}</span>
                        <Button
                          isIconOnly
                          size="sm"
                          variant="light"
                          onPress={() => copyToClipboard(assetType)}
                        >
                          <Copy className="w-4 h-4" />
                        </Button>
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <span>{truncateAddress(priceInfo.aggregator)}</span>
                        <Button
                          isIconOnly
                          size="sm"
                          variant="light"
                          onPress={() => copyToClipboard(priceInfo.aggregator)}
                        >
                          <Copy className="w-4 h-4" />
                        </Button>
                      </div>
                    </TableCell>
                    <TableCell>{priceInfo.decimals}</TableCell>
                    <TableCell>
                      {formatValue(priceInfo.price, priceInfo.decimals)}
                    </TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <span>{formatTimestamp(priceInfo.last_updated)}</span>
                        <Popover showArrow>
                          <PopoverTrigger>
                            <Button
                              isIconOnly
                              className="min-w-0 w-4 h-4"
                              size="sm"
                              variant="light"
                            >
                              <InfoCircle className="w-3 h-3" />
                            </Button>
                          </PopoverTrigger>
                          <PopoverContent>
                            <div className="px-1 py-2 space-y-1">
                              <div className="text-sm">
                                <div className="font-semibold">Timestamp:</div>
                                <div>{priceInfo.last_updated}</div>
                              </div>
                              <div className="text-sm">
                                <div className="font-semibold">Formatted:</div>
                                <div>
                                  {dayjs(priceInfo.last_updated).format(
                                    "YYYY-MM-DD HH:mm:ss",
                                  )}
                                </div>
                              </div>
                            </div>
                          </PopoverContent>
                        </Popover>
                      </div>
                    </TableCell>
                    <TableCell>
                      {hasAdminCap ? (
                        <div className="flex gap-2">
                          <Button
                            color="primary"
                            size="sm"
                            variant="flat"
                            onPress={() => {
                              setChangingAssetType(assetType);
                              setNewAggregatorId("");
                            }}
                          >
                            Change
                          </Button>
                          <Button
                            color="danger"
                            isLoading={
                              isRemoving && removingAssetType === assetType
                            }
                            size="sm"
                            variant="flat"
                            onPress={() => handleRemoveAggregator(assetType)}
                          >
                            <Trash className="w-4 h-4" />
                          </Button>
                        </div>
                      ) : (
                        <span className="text-default-400 text-sm">—</span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardBody>
      </Card>

      {/* Add Aggregator Modal */}
      <AddAggregatorModal
        isAdding={isAdding}
        isOpen={isAddModalOpen}
        onAdd={handleAddAggregator}
        onClose={() => setIsAddModalOpen(false)}
      />

      {/* Edit Config Modal */}
      <Modal
        isOpen={isEditConfigModalOpen}
        onClose={() => setIsEditConfigModalOpen(false)}
      >
        <ModalContent>
          <ModalHeader>Edit Configuration</ModalHeader>
          <ModalBody>
            {isEditingConfig ? (
              <div className="flex items-center justify-center py-8">
                <Spinner size="lg" />
              </div>
            ) : (
              <div className="space-y-4">
                <Input
                  description="Leave empty to keep current value"
                  label="Update Interval (milliseconds)"
                  placeholder={oracleConfig.update_interval.toString()}
                  type="number"
                  value={updateInterval}
                  onValueChange={setUpdateInterval}
                />
                <Input
                  description="Leave empty to keep current value"
                  label="DEX Slippage (u256, e.g., 100 for 1%)"
                  placeholder={oracleConfig.dex_slippage}
                  value={dexSlippage}
                  onValueChange={setDexSlippage}
                />
              </div>
            )}
          </ModalBody>
          <ModalFooter>
            <Button
              variant="light"
              onPress={() => setIsEditConfigModalOpen(false)}
            >
              Cancel
            </Button>
            <Button
              color="primary"
              isLoading={isEditingConfig}
              onPress={handleUpdateConfig}
            >
              Update
            </Button>
          </ModalFooter>
        </ModalContent>
      </Modal>

      {/* Change Aggregator Modal */}
      <Modal
        isOpen={changingAssetType !== null}
        size="2xl"
        onClose={() => {
          setChangingAssetType(null);
          setNewAggregatorId("");
        }}
      >
        <ModalContent>
          <ModalHeader>Change Aggregator</ModalHeader>
          <ModalBody>
            <div className="space-y-4">
              <div>
                <div className="text-sm text-default-500">Asset Type</div>
                <div className="font-semibold">{changingAssetType}</div>
              </div>
              <Input
                description="Switchboard Aggregator object ID"
                label="New Aggregator ID"
                placeholder="0x..."
                value={newAggregatorId}
                onValueChange={setNewAggregatorId}
              />
              <div className="pt-4">
                <SwitchboardAggregatorBrowser
                  onSelect={(id) => {
                    setNewAggregatorId(id);
                  }}
                />
              </div>
            </div>
          </ModalBody>
          <ModalFooter>
            <Button
              variant="light"
              onPress={() => {
                setChangingAssetType(null);
                setNewAggregatorId("");
              }}
            >
              Cancel
            </Button>
            <Button
              color="primary"
              isLoading={isChanging}
              onPress={handleChangeAggregator}
            >
              Change
            </Button>
          </ModalFooter>
        </ModalContent>
      </Modal>
    </div>
  );
}
