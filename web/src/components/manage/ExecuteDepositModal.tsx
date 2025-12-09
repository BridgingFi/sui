import type { VaultInfo } from "@/lib/types";
import type { DepositRequest } from "@/hooks/useVaultRequests";

import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import {
  addToast,
  Button,
  Checkbox,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Spinner,
} from "@heroui/react";
import { useState } from "react";

import { VAULT_DECIMALS } from "@/lib/constants";
import { isBridgingFiPosition } from "@/utils/bridgingfi";
import { formatCoinAmount, formatDecimal } from "@/utils/format";
import { loggers } from "@/utils/debug";
import {
  extractBuildError,
  showTransactionErrorToast,
} from "@/utils/transaction";

const { errorLog, debugLog } = loggers("app:manage:execute-deposit-modal");

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";
const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";

interface ExecuteDepositModalProps {
  vault: VaultInfo;
  request: DepositRequest | null;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  operatorCaps: Array<{ objectId: string }> | undefined;
  assetTypes: string[] | undefined;
  coinDecimals: number | null;
}

export function ExecuteDepositModal({
  vault,
  request,
  isOpen,
  onClose,
  onSuccess,
  operatorCaps,
  assetTypes,
  coinDecimals,
}: ExecuteDepositModalProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  const [dryrunResult, setDryrunResult] = useState<{
    shares: string;
    shareRatio: string;
    totalUsdValueBefore?: string;
    totalUsdValueAfter?: string;
    usdValueDeposited?: string;
    shareRatioFromEvent?: string;
    simulatedShares?: string;
    sharesDifference?: string;
    isLoading: boolean;
    error?: string;
  } | null>(null);
  const [updateSwitchboardPrice, setUpdateSwitchboardPrice] = useState(false);
  const [updateOraclePrice, setUpdateOraclePrice] = useState(false);
  const [cachedTransaction, setCachedTransaction] =
    useState<Transaction | null>(null);
  const [isExecuting, setIsExecuting] = useState(false);

  // Build transaction for execute_deposit (used for both dryrun and execution)
  const buildExecuteDepositTransaction = (
    request: DepositRequest,
    operatorCap: { objectId: string },
    maxSharesReceived: bigint,
  ): Transaction => {
    const tx = new Transaction();

    // Extract coin type from vault coin_type
    const coinType = vault.coin_type;

    if (!coinType) {
      throw new Error("Coin type is missing from vault");
    }

    debugLog(
      "Executing deposit - Note: Currently only updating principal token value before execution. " +
        "Other asset types (coin_type assets, Defi positions) are not updated. " +
        "Future implementation needed to update all asset types before and after execute_deposit.",
    );

    // Update principal value before execute_deposit because execute_deposit
    // calls get_total_usd_value (line 820) which requires all assets to be
    // updated within MAX_UPDATE_INTERVAL which is 0.
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::vault::update_free_principal_value`,
      typeArguments: [coinType],
      arguments: [
        tx.object(vault.vault_id),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    // Update BridgingFiPosition values before execute_deposit
    // This is required because execute_deposit checks all asset values are updated within MAX_UPDATE_INTERVAL
    if (assetTypes && VOLO_ORACLE_CONFIG_ID) {
      const bridgingFiAssetTypes = assetTypes.filter((assetType) =>
        isBridgingFiPosition(assetType),
      );

      for (const bridgingFiAssetType of bridgingFiAssetTypes) {
        debugLog(
          "BridgingFiPosition found, updating value before execute_deposit. AssetType: %s",
          bridgingFiAssetType,
        );

        tx.moveCall({
          target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::update_value`,
          typeArguments: [coinType],
          arguments: [
            tx.object(vault.vault_id),
            tx.object(VOLO_ORACLE_CONFIG_ID),
            tx.object(SUI_CLOCK_OBJECT_ID),
            tx.pure.string(bridgingFiAssetType),
          ],
        });
      }
    }

    // Call execute_deposit with provided max_shares_received
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::execute_deposit`,
      typeArguments: [coinType],
      arguments: [
        tx.object(VOLO_OPERATION_ID),
        tx.object(operatorCap.objectId),
        tx.object(vault.vault_id),
        tx.object(vault.reward_manager_id),
        tx.object(SUI_CLOCK_OBJECT_ID),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.pure.u64(request.request_id),
        tx.pure.u256(maxSharesReceived),
      ],
    });

    return tx;
  };

  const handleOpen = async () => {
    if (!request || !currentAccount) {
      return;
    }

    // Validate request data
    if (!request.request_id || !request.expected_shares) {
      addToast({
        title: "Invalid request data",
        description: "Request ID or expected shares is missing",
        color: "danger",
      });

      return;
    }

    // Validate deposit request amount (defensive check to avoid wasting gas)
    if (BigInt(String(request.amount || 0)) === 0n) {
      addToast({
        title: "Invalid request",
        description: "Deposit request amount is zero",
        color: "danger",
      });

      return;
    }

    // Set loading state
    setDryrunResult({
      shares: "",
      shareRatio: "",
      totalUsdValueBefore: undefined,
      totalUsdValueAfter: undefined,
      usdValueDeposited: undefined,
      shareRatioFromEvent: undefined,
      simulatedShares: undefined,
      sharesDifference: undefined,
      isLoading: true,
    });

    // Perform dryrun to get simulation results
    try {
      // Get first available OperatorCap
      const operatorCap = operatorCaps?.[0];

      if (!operatorCap) {
        throw new Error("You need an OperatorCap to execute deposits");
      }

      // Step 1: dryrun with u256::MAX to get estimated shares
      const u256Max = BigInt(
        "115792089237316195423570985008687907853269984665640564039457584007913129639935",
      );

      const firstTx = buildExecuteDepositTransaction(
        request,
        operatorCap,
        u256Max,
      );

      // Set sender for dryrun (required for dryRunTransactionBlock)
      firstTx.setSender(currentAccount.address);

      // Build the transaction for dryrun
      const firstTxBytes = await firstTx
        .build({ client })
        .catch(extractBuildError);

      // Now dryrun the transaction to extract actual shares and events
      const firstDryrunResult = await client.dryRunTransactionBlock({
        transactionBlock: firstTxBytes,
      });

      debugLog("dryrun result: %o", firstDryrunResult);

      // Extract information from events
      let actualShares: string | null = null;
      let totalUsdValueBefore: string | null = null;
      let totalUsdValueAfter: string | null = null;
      let shareRatioBefore: string | null = null;

      if (
        firstDryrunResult.effects?.status?.status === "success" &&
        firstDryrunResult.events
      ) {
        // Extract DepositExecuted event for shares
        const depositEvent = firstDryrunResult.events.find((event) =>
          event.type.includes("DepositExecuted"),
        );

        if (depositEvent?.parsedJson) {
          const parsed = depositEvent.parsedJson as {
            shares?: string | number;
          };

          if (parsed.shares !== undefined) {
            actualShares =
              typeof parsed.shares === "string"
                ? parsed.shares
                : String(parsed.shares);
          }
        }

        // Extract TotalUSDValueUpdated events (before and after)
        const totalUsdValueEvents = firstDryrunResult.events.filter((event) =>
          event.type.includes("TotalUSDValueUpdated"),
        );

        // Find the first and last TotalUSDValueUpdated events
        if (totalUsdValueEvents.length >= 1) {
          const firstEvent = totalUsdValueEvents[0];

          if (firstEvent?.parsedJson) {
            const parsed = firstEvent.parsedJson as {
              total_usd_value?: string | number;
            };

            if (parsed.total_usd_value !== undefined) {
              totalUsdValueBefore =
                typeof parsed.total_usd_value === "string"
                  ? parsed.total_usd_value
                  : String(parsed.total_usd_value);
            }
          }
        }

        if (totalUsdValueEvents.length >= 2) {
          const lastEvent = totalUsdValueEvents[totalUsdValueEvents.length - 1];

          if (lastEvent?.parsedJson) {
            const parsed = lastEvent.parsedJson as {
              total_usd_value?: string | number;
            };

            if (parsed.total_usd_value !== undefined) {
              totalUsdValueAfter =
                typeof parsed.total_usd_value === "string"
                  ? parsed.total_usd_value
                  : String(parsed.total_usd_value);
            }
          }
        } else if (totalUsdValueEvents.length === 1) {
          // If only one event, it's the after value
          const event = totalUsdValueEvents[0];

          if (event?.parsedJson) {
            const parsed = event.parsedJson as {
              total_usd_value?: string | number;
            };

            if (parsed.total_usd_value !== undefined) {
              totalUsdValueAfter =
                typeof parsed.total_usd_value === "string"
                  ? parsed.total_usd_value
                  : String(parsed.total_usd_value);
            }
          }
        }

        // Extract ShareRatioUpdated event (should be only one, before deposit)
        const shareRatioEvent = firstDryrunResult.events.find((event) =>
          event.type.includes("ShareRatioUpdated"),
        );

        if (shareRatioEvent?.parsedJson) {
          const parsed = shareRatioEvent.parsedJson as {
            share_ratio?: string | number;
          };

          if (parsed.share_ratio !== undefined) {
            shareRatioBefore =
              typeof parsed.share_ratio === "string"
                ? parsed.share_ratio
                : String(parsed.share_ratio);
          }
        }
      }

      // Default shareRatioBefore to 1 * DECIMALS if not found
      if (!shareRatioBefore) {
        shareRatioBefore = String(VAULT_DECIMALS);
      }

      if (!actualShares) {
        throw new Error("Failed to extract shares from dryrun result");
      }

      // Step 2: Build transaction with actual shares
      const actualSharesBigInt = BigInt(actualShares);

      const finalTx = buildExecuteDepositTransaction(
        request,
        operatorCap,
        actualSharesBigInt,
      );

      finalTx.setSender(currentAccount.address);

      // Step 3: Verify the final transaction can pass build without errors
      await finalTx.build({ client }).catch(extractBuildError);

      // Step 4: Calculate values from events and simulate shares
      let usdValueDeposited: string | null = null;

      if (totalUsdValueBefore && totalUsdValueAfter) {
        const before = BigInt(totalUsdValueBefore);
        const after = BigInt(totalUsdValueAfter);
        const deposited = after - before;

        usdValueDeposited = deposited.toString();
      }

      // Simulate shares using share_ratio_before from event
      let simulatedShares: string | null = null;
      let sharesDifference: string | null = null;

      if (shareRatioBefore && usdValueDeposited) {
        const usdValueDepositedBigInt = BigInt(usdValueDeposited);
        const shareRatioBeforeBigInt = BigInt(shareRatioBefore);

        // Simulate: shares = div_d(usdValueDeposited, shareRatioBefore)
        simulatedShares = (
          (usdValueDepositedBigInt * VAULT_DECIMALS) /
          shareRatioBeforeBigInt
        ).toString();

        // Calculate difference between simulated and actual shares
        const simulatedBigInt = BigInt(simulatedShares);
        const actualBigInt = actualSharesBigInt;
        const difference = actualBigInt - simulatedBigInt;

        sharesDifference = difference.toString();
      }

      // Use share_ratio_before for display
      const shareRatioForDisplay = shareRatioBefore || "";

      // Cache the final transaction for execution
      setCachedTransaction(finalTx);

      setDryrunResult({
        shares: actualShares,
        shareRatio: shareRatioForDisplay,
        totalUsdValueBefore: totalUsdValueBefore || undefined,
        totalUsdValueAfter: totalUsdValueAfter || undefined,
        usdValueDeposited: usdValueDeposited || undefined,
        shareRatioFromEvent: shareRatioBefore || undefined,
        simulatedShares: simulatedShares || undefined,
        sharesDifference: sharesDifference || undefined,
        isLoading: false,
      });
    } catch (err) {
      setDryrunResult({
        shares: "",
        shareRatio: "",
        totalUsdValueBefore: undefined,
        totalUsdValueAfter: undefined,
        usdValueDeposited: undefined,
        shareRatioFromEvent: undefined,
        simulatedShares: undefined,
        sharesDifference: undefined,
        isLoading: false,
        error:
          err instanceof Error ? err.message : String(err ?? "Unknown error"),
      });

      // Clear cached transaction on error
      setCachedTransaction(null);

      errorLog("Dryrun failed: %O", err);
    }
  };

  const handleClose = () => {
    setDryrunResult(null);
    setCachedTransaction(null);
    setUpdateSwitchboardPrice(false);
    setUpdateOraclePrice(false);
    setIsExecuting(false);
    onClose();
  };

  const handleConfirmExecute = async () => {
    if (!request || !currentAccount) {
      return;
    }

    // Get first available OperatorCap
    const operatorCap = operatorCaps?.[0];

    if (!operatorCap) {
      addToast({
        title: "No OperatorCap found",
        description: "You need an OperatorCap to execute deposits",
        color: "danger",
      });

      return;
    }

    setIsExecuting(true);

    try {
      debugLog(
        "Executing deposit - request_id:%s amount:%s expected_shares:%s",
        request.request_id,
        request.amount,
        request.expected_shares,
      );

      // Use cached transaction from dryrun to ensure consistency
      let tx = cachedTransaction;

      if (!tx) {
        throw new Error("Cached transaction not found. Please retry.");
      }

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setIsExecuting(false);
            setDryrunResult(null);
            setCachedTransaction(null);
            handleClose();
            addToast({
              title: "Success",
              description: "Deposit executed successfully",
              color: "success",
            });
            // Wait a bit for events to be indexed
            setTimeout(() => {
              onSuccess();
            }, 2000);
          },
          onError: (err) => {
            setIsExecuting(false);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Execute deposit failed",
            );
          },
        },
      );
    } catch (err) {
      setIsExecuting(false);

      errorLog("Execute deposit hook error: %O", err);

      addToast({
        title: "Execute deposit failed",
        description:
          err instanceof Error ? err.message : String(err ?? "Unknown error"),
        color: "danger",
      });
    }
  };

  // Trigger dryrun when modal opens
  if (isOpen && request && !dryrunResult && !isExecuting) {
    handleOpen();
  }

  return (
    <Modal
      isOpen={isOpen}
      scrollBehavior="inside"
      size="lg"
      onClose={handleClose}
    >
      <ModalContent>
        <ModalHeader>Confirm Deposit Execution</ModalHeader>
        <ModalBody>
          {request && (
            <div className="space-y-4">
              <div>
                <p className="text-sm text-default-500">Request ID</p>
                <p className="font-mono text-sm">{request.request_id}</p>
              </div>

              <div>
                <p className="text-sm text-default-500">Deposit Amount</p>
                <p className="font-medium">
                  {formatCoinAmount(request.amount, coinDecimals)}{" "}
                  {vault.coin_type?.split("::").pop() || ""}
                </p>
              </div>

              {dryrunResult?.isLoading ? (
                <div className="flex items-center gap-2 py-4">
                  <Spinner size="sm" />
                  <p className="text-sm text-default-500">
                    Simulating transaction...
                  </p>
                </div>
              ) : dryrunResult?.error ? (
                <div className="space-y-2 rounded-lg bg-danger-50 p-3">
                  <div>
                    <p className="text-sm font-medium text-danger">
                      Simulation failed
                    </p>
                    <p className="text-sm text-danger">{dryrunResult.error}</p>
                  </div>
                </div>
              ) : (
                <>
                  <div>
                    <p className="text-sm text-default-500">
                      Expected Shares (from request)
                    </p>
                    <p className="font-mono text-sm">
                      {formatDecimal(
                        String(request.expected_shares),
                        VAULT_DECIMALS,
                        {
                          maximumFractionDigits: 9,
                        },
                      ) ?? "N/A"}
                    </p>
                  </div>

                  {dryrunResult?.shares && (
                    <div>
                      <p className="text-sm text-default-500">
                        Actual Shares (from dryrun)
                      </p>
                      <p className="font-mono text-sm font-medium">
                        {formatDecimal(dryrunResult.shares, VAULT_DECIMALS, {
                          maximumFractionDigits: 9,
                        }) ?? "N/A"}
                      </p>
                    </div>
                  )}

                  {dryrunResult?.totalUsdValueBefore !== undefined &&
                    dryrunResult?.totalUsdValueAfter !== undefined && (
                      <div className="space-y-1 rounded-lg bg-default-50 p-3">
                        <p className="text-xs font-medium text-default-700">
                          Total USD Value (from events)
                        </p>
                        <div className="space-y-1 text-xs">
                          <div className="flex justify-between">
                            <span className="text-default-500">Before:</span>
                            <span className="font-mono">
                              {formatCoinAmount(
                                dryrunResult.totalUsdValueBefore,
                                9,
                              )}
                            </span>
                          </div>
                          <div className="flex justify-between">
                            <span className="text-default-500">After:</span>
                            <span className="font-mono">
                              {formatCoinAmount(
                                dryrunResult.totalUsdValueAfter,
                                9,
                              )}
                            </span>
                          </div>
                          {dryrunResult?.usdValueDeposited && (
                            <div className="flex justify-between border-t border-default-200 pt-1">
                              <span className="font-medium text-default-700">
                                Deposited:
                              </span>
                              <span className="font-mono font-medium">
                                {formatCoinAmount(
                                  dryrunResult.usdValueDeposited,
                                  9,
                                )}
                              </span>
                            </div>
                          )}
                        </div>
                      </div>
                    )}

                  {dryrunResult?.shareRatioFromEvent && (
                    <div>
                      <p className="text-sm text-default-500">
                        Share Ratio (from event)
                      </p>
                      <p className="font-mono text-sm">
                        {formatCoinAmount(dryrunResult.shareRatioFromEvent, 9)}
                      </p>
                    </div>
                  )}

                  {dryrunResult?.simulatedShares && (
                    <div>
                      <p className="text-sm text-default-500">
                        Simulated Shares (calculated from events)
                      </p>
                      <p className="font-mono text-sm">
                        {formatDecimal(
                          dryrunResult.simulatedShares,
                          VAULT_DECIMALS,
                          {
                            maximumFractionDigits: 9,
                          },
                        ) ?? "N/A"}
                      </p>
                      <p className="text-xs text-default-400">
                        Calculated: (usdValueDeposited × DECIMALS) / shareRatio
                      </p>
                    </div>
                  )}

                  {dryrunResult?.sharesDifference !== undefined && (
                    <div>
                      <p className="text-sm text-default-500">
                        Shares Difference (Actual - Simulated)
                      </p>
                      <p
                        className={`font-mono text-sm ${
                          Number(dryrunResult.sharesDifference) === 0
                            ? "text-success"
                            : Number(dryrunResult.sharesDifference) > 0
                              ? "text-warning"
                              : "text-danger"
                        }`}
                      >
                        {Number(dryrunResult.sharesDifference) === 0
                          ? "0 (Perfect match)"
                          : Number(dryrunResult.sharesDifference) > 0
                            ? `+${
                                formatDecimal(
                                  dryrunResult.sharesDifference,
                                  VAULT_DECIMALS,
                                  {
                                    maximumFractionDigits: 9,
                                  },
                                ) ?? "N/A"
                              } (Actual higher)`
                            : `${
                                formatDecimal(
                                  dryrunResult.sharesDifference,
                                  VAULT_DECIMALS,
                                  {
                                    maximumFractionDigits: 9,
                                  },
                                ) ?? "N/A"
                              } (Actual lower)`}
                      </p>
                    </div>
                  )}
                </>
              )}

              <div className="space-y-2 border-t pt-4">
                <Checkbox
                  isDisabled={true}
                  isSelected={updateSwitchboardPrice}
                  onValueChange={setUpdateSwitchboardPrice}
                >
                  <div>
                    <p className="text-sm font-medium">
                      Update Switchboard Aggregator Prices
                    </p>
                    <p className="text-xs text-default-500">
                      Future: Update Switchboard aggregator prices before
                      execution
                    </p>
                  </div>
                </Checkbox>

                <Checkbox
                  isDisabled={true}
                  isSelected={updateOraclePrice}
                  onValueChange={setUpdateOraclePrice}
                >
                  <div>
                    <p className="text-sm font-medium">
                      Update OracleConfig Prices
                    </p>
                    <p className="text-xs text-default-500">
                      Future: Update OracleConfig prices from aggregators
                    </p>
                  </div>
                </Checkbox>
              </div>
            </div>
          )}
        </ModalBody>
        <ModalFooter>
          <Button variant="light" onPress={handleClose}>
            Cancel
          </Button>
          <Button
            color="primary"
            isDisabled={
              dryrunResult?.isLoading ||
              !!dryrunResult?.error ||
              !request ||
              isExecuting ||
              isPending
            }
            isLoading={isExecuting || isPending}
            onPress={handleConfirmExecute}
          >
            Confirm & Execute
          </Button>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
