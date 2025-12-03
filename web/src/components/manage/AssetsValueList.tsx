import type { VaultInfo } from "@/lib/types";

import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
} from "@heroui/react";
import { Trash, Xmark } from "iconoir-react";
import { useState, useMemo } from "react";
import dayjs from "dayjs";
import utc from "dayjs/plugin/utc";

dayjs.extend(utc);

import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { useVaultAssets, type AssetValueInfo } from "@/hooks/useVaultAssets";
import { useBridgingFiPosition } from "@/hooks/useBridgingFiPosition";
import { useOracleConfig } from "@/hooks/useOracleConfig";
import { InvestmentForm } from "@/components/manage/InvestmentForm";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";

const { errorLog } = loggers("app:manage:assets-value-list");

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";

interface AssetsValueListProps {
  vault: VaultInfo;
  assetTypes: string[] | null;
  onCreatePosition?: () => void;
}

function formatAmount(amount: number, decimals: number = 6): string {
  return (amount / Math.pow(10, decimals)).toFixed(6);
}

/**
 * Check if an asset type is a DeFi asset (not PrincipalCoinType)
 * DeFi assets have index suffix like "Type0", "Type1", etc.
 */
function isDeFiAsset(assetType: string): boolean {
  // Check if asset type ends with digits (index suffix)
  return /\d+$/.test(assetType);
}

/**
 * Check if an asset type is a BridgingFiPosition
 */
function isBridgingFiPosition(assetType: string): boolean {
  return assetType.includes("bridgingfi_adapter::BridgingFiPosition");
}

/**
 * Extract DeFi asset index from asset type
 * Format: ...::module::Type{idx}
 * Returns the index number, or null if not found
 */
function extractDeFiAssetIndex(assetType: string): number | null {
  const match = assetType.match(/(\d+)$/);

  if (match && match[1]) {
    return parseInt(match[1], 10);
  }

  return null;
}

/**
 * Assets Value List Component
 * Displays all vault assets with their USD values and last updated times
 * Allows removing BridgingFiPosition assets (except PrincipalCoinType which is always first)
 */
export function AssetsValueList({
  vault,
  assetTypes,
  onCreatePosition,
}: AssetsValueListProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();
  const { operatorCaps } = useOperatorCaps();
  const { oracleConfig } = useOracleConfig();

  const coinType = vault.coin_type;

  // Get coin decimals from oracle config
  // Note: coinType comes from vault.coin_type, which is correct since position belongs to vault
  const coinDecimals = useMemo(() => {
    if (!oracleConfig) {
      throw new Error(
        `Oracle config not loaded. Cannot determine decimals for coin type: ${coinType}`,
      );
    }

    // Try to get decimals from oracle config using coin type
    // Remove 0x prefix if present for lookup
    const lookupKey = coinType.startsWith("0x") ? coinType.slice(2) : coinType;
    const priceInfo = oracleConfig.aggregators.get(lookupKey);

    if (!priceInfo || !priceInfo.decimals) {
      throw new Error(
        `Decimals not found in oracle config for coin type: ${coinType}. Please ensure the coin type is configured in OracleConfig.`,
      );
    }

    return priceInfo.decimals;
  }, [oracleConfig, coinType]);

  // Query vault assets
  const { assets, isLoading: isLoadingAssets } = useVaultAssets(
    vault.vault_id,
    assetTypes || [],
  );

  // Remove position modal state
  const [isRemovePositionModalOpen, setIsRemovePositionModalOpen] =
    useState(false);
  const [selectedAsset, setSelectedAsset] = useState<AssetValueInfo | null>(
    null,
  );

  // Detail display state
  const [expandedAssetType, setExpandedAssetType] = useState<string | null>(
    null,
  );

  // Investment modal state
  const [isInvestmentModalOpen, setIsInvestmentModalOpen] = useState(false);

  // Query BridgingFiPosition details when an asset is expanded
  const {
    position: bridgingFiPosition,
    isLoading: isLoadingBridgingFiPosition,
  } = useBridgingFiPosition(
    vault.vault_id,
    coinType || null,
    expandedAssetType,
  );

  const handleRemoveClick = (asset: AssetValueInfo) => {
    setSelectedAsset(asset);
    setIsRemovePositionModalOpen(true);
  };

  const handleRemoveConfirm = async () => {
    if (
      !currentAccount ||
      !operatorCaps ||
      operatorCaps.length === 0 ||
      !selectedAsset
    ) {
      return;
    }

    const operatorCap = operatorCaps[0];

    if (!operatorCap) {
      return;
    }

    // Extract DeFi asset index
    const defiAssetId = extractDeFiAssetIndex(selectedAsset.assetType);

    if (defiAssetId === null) {
      errorLog(
        "Failed to extract DeFi asset index from assetType: %s",
        selectedAsset.assetType,
      );

      return;
    }

    // Get full type name from assetType, add 0x prefix if needed
    // assetType format: <address>::module::Type{idx} or 0x<address>::module::Type{idx}
    // For type arguments, we need: 0x<address>::module::Type (without idx)
    let fullTypeName = selectedAsset.assetType;

    // Remove index suffix (e.g., "BridgingFiPosition0" -> "BridgingFiPosition")
    // Match any type name ending with digits (not just BridgingFiPosition)
    fullTypeName = fullTypeName.replace(/\d+$/, "");

    // Add 0x prefix if not present
    if (!fullTypeName.startsWith("0x")) {
      // Find the first :: to determine where the address ends
      const firstColonIndex = fullTypeName.indexOf("::");

      if (firstColonIndex > 0) {
        // Add 0x prefix to address part
        fullTypeName = `0x${fullTypeName}`;
      }
    }

    try {
      const tx = new Transaction();

      // Remove asset from vault using the full type name from the list
      // This returns the removed asset (AssetType) which must be transferred or used
      const removedAsset = tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::remove_defi_asset_support`,
        typeArguments: [coinType, fullTypeName],
        arguments: [
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          tx.object(vault.vault_id),
          tx.pure.u8(defiAssetId),
        ],
      });

      // Transfer the removed asset to the sender to avoid UnusedValueWithoutDrop error
      // The asset doesn't have 'drop' ability, so it must be transferred or used
      tx.transferObjects([removedAsset], currentAccount.address);

      signAndExecute(
        {
          transaction: tx as any,
        },
        {
          onSuccess: () => {
            setIsRemovePositionModalOpen(false);
            setSelectedAsset(null);
            // Assets will automatically refetch when assetTypes change
          },
          onError: (err) => {
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Failed to remove BridgingFiPosition",
            );
          },
        },
      );
    } catch (err) {
      errorLog("Remove position error: %O", err);
    }
  };

  if (!assetTypes || assetTypes.length === 0) {
    return null;
  }

  return (
    <>
      <Card>
        <CardHeader className="flex items-center justify-between">
          <span>Assets Value</span>
          {onCreatePosition && (
            <Button
              color="primary"
              isDisabled={!currentAccount}
              size="sm"
              variant="bordered"
              onPress={onCreatePosition}
            >
              Add Position
            </Button>
          )}
        </CardHeader>
        <Divider />
        <CardBody className="p-0">
          {isLoadingAssets ? (
            <div className="flex items-center gap-2 p-4">
              <Spinner size="sm" />
              <span className="text-sm text-default-500">Loading...</span>
            </div>
          ) : assets.length === 0 ? (
            <div className="text-center py-4 px-4 text-default-500">
              <p>No assets found.</p>
            </div>
          ) : (
            <Table
              aria-label="Assets value"
              classNames={{
                wrapper: ["p-0", "rounded-none"],
                th: ["first:rounded-s-none", "last:rounded-e-none"],
              }}
            >
              <TableHeader>
                <TableColumn>ASSET TYPE</TableColumn>
                <TableColumn>USD VALUE</TableColumn>
                <TableColumn>LAST UPDATED</TableColumn>
                <TableColumn>ACTIONS</TableColumn>
              </TableHeader>
              <TableBody>
                {assets.map((asset, index) => {
                  // First element is PrincipalCoinType, cannot be removed
                  const isPrincipalCoinType = index === 0;
                  const canRemove =
                    !isPrincipalCoinType && isDeFiAsset(asset.assetType);

                  return (
                    <TableRow key={asset.assetType}>
                      <TableCell className="align-top">
                        <code className="text-sm break-all whitespace-normal">
                          {asset.assetType}
                        </code>
                      </TableCell>
                      <TableCell className="align-top">
                        <span className="font-mono text-sm">
                          {formatAmount(Number(asset.usdValue), 9)}
                        </span>
                      </TableCell>
                      <TableCell className="align-top">
                        <span className="text-sm">
                          {asset.lastUpdated > 0
                            ? `${dayjs
                                .utc(asset.lastUpdated)
                                .format("YYYY-MM-DD HH:mm:ss")} (UTC)`
                            : "Never"}
                        </span>
                      </TableCell>
                      <TableCell className="align-top flex gap-1">
                        {isBridgingFiPosition(asset.assetType) && (
                          <Button
                            color="primary"
                            isDisabled={!currentAccount}
                            size="sm"
                            variant="bordered"
                            onPress={() => {
                              setExpandedAssetType(
                                expandedAssetType === asset.assetType
                                  ? null
                                  : asset.assetType,
                              );
                            }}
                          >
                            {expandedAssetType === asset.assetType
                              ? "Hide"
                              : "Details"}
                          </Button>
                        )}
                        {canRemove ? (
                          <Button
                            isIconOnly
                            color="danger"
                            isDisabled={!currentAccount || isPending}
                            size="sm"
                            variant="light"
                            onPress={() => handleRemoveClick(asset)}
                          >
                            <Trash className="w-4 h-4" />
                          </Button>
                        ) : !isBridgingFiPosition(asset.assetType) ? (
                          <span className="text-xs text-default-400">
                            {isPrincipalCoinType ? "Principal" : "-"}
                          </span>
                        ) : null}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}

          {/* BridgingFi Position Details - Display below table when expanded */}
          {expandedAssetType && isBridgingFiPosition(expandedAssetType) && (
            <div className="rounded-lg border border-default-200 bg-default-50 p-4 m-2 mt-0">
              {isLoadingBridgingFiPosition ? (
                <div className="flex items-center justify-center py-8">
                  <Spinner size="lg" />
                </div>
              ) : !bridgingFiPosition ? (
                <div className="text-center py-8 text-default-500">
                  <p>Position not found or not loaded.</p>
                </div>
              ) : (
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <span>BridgingFi Position Details</span>
                    <Button
                      isIconOnly
                      size="sm"
                      variant="light"
                      onPress={() => setExpandedAssetType(null)}
                    >
                      <Xmark className="w-4 h-4" />
                    </Button>
                  </div>
                  <div className="space-y-1 text-sm">
                    <p>
                      <span className="text-default-500">
                        Position Object ID:
                      </span>{" "}
                      <code className="text-xs font-mono break-all">
                        {bridgingFiPosition.objectId}
                      </code>
                    </p>
                    <div className="flex items-center gap-2">
                      <p className="flex-1">
                        <span className="text-default-500">
                          Custodian Account:
                        </span>{" "}
                        <code className="text-xs font-mono break-all">
                          {bridgingFiPosition.custodianAccount}
                        </code>
                      </p>
                      <Button
                        color="primary"
                        isDisabled={!currentAccount}
                        size="sm"
                        variant="bordered"
                        onPress={() => setIsInvestmentModalOpen(true)}
                      >
                        Invest to Custodian
                      </Button>
                    </div>
                    <p>
                      <span className="text-default-500">APR:</span>{" "}
                      <span className="font-mono">
                        {bridgingFiPosition.aprPercentage}
                      </span>
                    </p>
                  </div>
                  <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                    <div className="rounded-lg bg-default-100 p-3">
                      <p className="text-sm font-semibold text-default-600">
                        Outstanding Balance
                      </p>
                      <p className="text-sm font-mono">
                        {formatAmount(
                          Number(bridgingFiPosition.outstandingBalance),
                          coinDecimals,
                        )}
                      </p>
                      <p className="text-xs text-default-500 mt-1">
                        Last Updated: {bridgingFiPosition.lastUpdateDate} (UTC)
                      </p>
                    </div>
                    <div className="rounded-lg bg-default-100 p-3">
                      <p className="text-sm font-semibold text-default-600">
                        Current Debt (Estimated)
                      </p>
                      <p className="text-sm font-mono">
                        {formatAmount(
                          Number(bridgingFiPosition.currentDebt),
                          coinDecimals,
                        )}
                      </p>
                      {bridgingFiPosition.currentDebtCalculatedAt && (
                        <p className="text-xs text-default-500 mt-1">
                          Estimated at:{" "}
                          {dayjs
                            .utc(bridgingFiPosition.currentDebtCalculatedAt)
                            .format("YYYY-MM-DD HH:mm:ss")}{" "}
                          (UTC)
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              )}
            </div>
          )}
        </CardBody>
      </Card>

      {/* Investment Modal */}
      {bridgingFiPosition && expandedAssetType && (
        <InvestmentForm
          assetType={expandedAssetType}
          isOpen={isInvestmentModalOpen}
          position={bridgingFiPosition}
          vault={vault}
          onClose={() => setIsInvestmentModalOpen(false)}
          onSuccess={() => {
            setIsInvestmentModalOpen(false);
            // Refresh position data
            // The hook will automatically refetch when dependencies change
          }}
        />
      )}

      {/* Remove Position Modal */}
      {selectedAsset && (
        <Modal
          isOpen={isRemovePositionModalOpen}
          size="lg"
          onClose={() => {
            setIsRemovePositionModalOpen(false);
            setSelectedAsset(null);
          }}
        >
          <ModalContent>
            <ModalHeader>Remove BridgingFi Position</ModalHeader>
            <ModalBody>
              <div className="space-y-4">
                <p className="text-sm text-default-600">
                  Are you sure you want to remove this BridgingFiPosition from
                  the vault? This action cannot be undone.
                </p>
                <div className="rounded-lg bg-warning-50 dark:bg-warning-900/20 p-4">
                  <p className="text-sm font-semibold text-warning">Warning</p>
                  <p className="text-sm text-warning mt-1">
                    This will permanently remove the BridgingFiPosition from the
                    vault. Make sure the position has no outstanding balance
                    before removing.
                  </p>
                </div>
                <div className="rounded-lg bg-default-100 p-4 space-y-2">
                  <p className="text-sm font-semibold">Position Information</p>
                  <div className="text-sm">
                    <p className="text-default-500">Asset Type</p>
                    <code className="text-xs">{selectedAsset.assetType}</code>
                  </div>
                  <div className="text-sm">
                    <p className="text-default-500">USD Value</p>
                    <p className="font-mono">
                      {formatAmount(Number(selectedAsset.usdValue), 9)}
                    </p>
                  </div>
                  <div className="text-sm">
                    <p className="text-default-500">Last Updated</p>
                    <p className="font-medium">
                      {selectedAsset.lastUpdated > 0
                        ? `${dayjs
                            .utc(selectedAsset.lastUpdated)
                            .format("YYYY-MM-DD HH:mm:ss")} (UTC)`
                        : "Never"}
                    </p>
                  </div>
                </div>
              </div>
            </ModalBody>
            <ModalFooter>
              <Button
                variant="light"
                onPress={() => {
                  setIsRemovePositionModalOpen(false);
                  setSelectedAsset(null);
                }}
              >
                Cancel
              </Button>
              <Button
                color="danger"
                isDisabled={
                  !currentAccount ||
                  !operatorCaps ||
                  operatorCaps.length === 0 ||
                  isPending
                }
                isLoading={isPending}
                onPress={handleRemoveConfirm}
              >
                Remove Position
              </Button>
            </ModalFooter>
          </ModalContent>
        </Modal>
      )}
    </>
  );
}
