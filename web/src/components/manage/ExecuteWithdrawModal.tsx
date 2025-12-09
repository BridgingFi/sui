import type { VaultInfo } from "@/lib/types";
import type { WithdrawRequest } from "@/hooks/useVaultRequests";

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

const { errorLog, debugLog } = loggers("app:manage:execute-withdraw-modal");

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";
const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";

interface ExecuteWithdrawModalProps {
  vault: VaultInfo;
  request: WithdrawRequest | null;
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  operatorCaps: Array<{ objectId: string }> | undefined;
  assetTypes: string[] | undefined;
  coinDecimals: number | null;
}

export function ExecuteWithdrawModal({
  vault,
  request,
  isOpen,
  onClose,
  onSuccess,
  operatorCaps,
  assetTypes,
  coinDecimals,
}: ExecuteWithdrawModalProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  const [dryrunResult, setDryrunResult] = useState<{
    shares: string;
    shareRatio: string;
    actualAmount?: string;
    totalUsdValueBefore?: string;
    totalUsdValueAfter?: string;
    usdValueWithdrawn?: string;
    shareRatioFromEvent?: string;
    balanceChanges?: Array<{
      coinType: string;
      amount: string;
    }>;
    isLoading: boolean;
    error?: string;
  } | null>(null);
  const [cachedTransaction, setCachedTransaction] =
    useState<Transaction | null>(null);
  const [isExecuting, setIsExecuting] = useState(false);

  // Build transaction for execute_withdraw (used for both dryrun and execution)
  const buildExecuteWithdrawTransaction = (
    request: WithdrawRequest,
    operatorCap: { objectId: string },
    maxAmountReceived: bigint,
  ): Transaction => {
    const tx = new Transaction();

    // Extract coin type from vault coin_type
    const coinType = vault.coin_type;

    if (!coinType) {
      throw new Error("Coin type is missing from vault");
    }

    debugLog(
      "Executing withdraw - Note: Currently only updating principal token value before execution. " +
        "Other asset types (coin_type assets, Defi positions) are not updated. " +
        "Future implementation needed to update all asset types before and after execute_withdraw.",
    );

    // Update principal value before execute_withdraw because execute_withdraw
    // calls get_total_usd_value which requires all assets to be updated within MAX_UPDATE_INTERVAL
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::vault::update_free_principal_value`,
      typeArguments: [coinType],
      arguments: [
        tx.object(vault.vault_id),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    // Update BridgingFiPosition values before execute_withdraw
    if (assetTypes && VOLO_ORACLE_CONFIG_ID) {
      const bridgingFiAssetTypes = assetTypes.filter((assetType) =>
        isBridgingFiPosition(assetType),
      );

      for (const bridgingFiAssetType of bridgingFiAssetTypes) {
        debugLog(
          "BridgingFiPosition found, updating value before execute_withdraw. AssetType: %s",
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

    // Call execute_withdraw with provided max_amount_received
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::execute_withdraw`,
      typeArguments: [coinType],
      arguments: [
        tx.object(VOLO_OPERATION_ID),
        tx.object(operatorCap.objectId),
        tx.object(vault.vault_id),
        tx.object(vault.reward_manager_id),
        tx.object(SUI_CLOCK_OBJECT_ID),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.pure.u64(request.request_id),
        tx.pure.u64(maxAmountReceived),
      ],
    });

    return tx;
  };

  const handleOpen = async () => {
    if (!request || !currentAccount) {
      return;
    }

    // Validate request data
    if (!request.request_id || !request.expected_amount) {
      addToast({
        title: "Invalid request data",
        description: "Request ID or expected amount is missing",
        color: "danger",
      });

      return;
    }

    // Validate withdraw request shares (defensive check to avoid wasting gas)
    if (BigInt(String(request.shares || 0)) === 0n) {
      addToast({
        title: "Invalid request",
        description: "Withdraw request shares is zero",
        color: "danger",
      });

      return;
    }

    // Set loading state
    setDryrunResult({
      shares: "",
      shareRatio: "",
      actualAmount: undefined,
      totalUsdValueBefore: undefined,
      totalUsdValueAfter: undefined,
      usdValueWithdrawn: undefined,
      shareRatioFromEvent: undefined,
      balanceChanges: undefined,
      isLoading: true,
    });

    // Perform dryrun to get simulation results
    try {
      // Get first available OperatorCap
      const operatorCap = operatorCaps?.[0];

      if (!operatorCap) {
        throw new Error("You need an OperatorCap to execute withdraws");
      }

      // Use u64::MAX for max_amount_received to get actual amount
      const u64Max = BigInt("18446744073709551615");

      const firstTx = buildExecuteWithdrawTransaction(
        request,
        operatorCap,
        u64Max,
      );

      // Set sender for dryrun (required for dryRunTransactionBlock)
      firstTx.setSender(currentAccount.address);

      // Build the transaction for dryrun
      const firstTxBytes = await firstTx
        .build({ client })
        .catch(extractBuildError);

      // Now dryrun the transaction to extract actual amount and events
      const firstDryrunResult = await client.dryRunTransactionBlock({
        transactionBlock: firstTxBytes,
      });

      debugLog("withdraw dryrun result: %o", firstDryrunResult);

      // Extract information from events and balanceChanges
      let actualAmount: string | null = null;
      let actualShares: string | null = null;
      let totalUsdValueBefore: string | null = null;
      let totalUsdValueAfter: string | null = null;
      let shareRatioFromEvent: string | null = null;
      const balanceChanges: Array<{ coinType: string; amount: string }> = [];

      if (
        firstDryrunResult.effects?.status?.status === "success" &&
        firstDryrunResult.events
      ) {
        // Extract WithdrawExecuted event for amount and shares
        const withdrawEvent = firstDryrunResult.events.find((event) =>
          event.type.includes("WithdrawExecuted"),
        );

        if (withdrawEvent?.parsedJson) {
          const parsed = withdrawEvent.parsedJson as {
            amount?: string | number;
            shares?: string | number;
          };

          if (parsed.amount !== undefined) {
            actualAmount =
              typeof parsed.amount === "string"
                ? parsed.amount
                : String(parsed.amount);
          }

          if (parsed.shares !== undefined) {
            actualShares =
              typeof parsed.shares === "string"
                ? parsed.shares
                : String(parsed.shares);
          }
        }

        // Extract ShareRatioUpdated event
        const shareRatioEvent = firstDryrunResult.events.find((event) =>
          event.type.includes("ShareRatioUpdated"),
        );

        if (shareRatioEvent?.parsedJson) {
          const parsed = shareRatioEvent.parsedJson as {
            share_ratio?: string | number;
          };

          if (parsed.share_ratio !== undefined) {
            shareRatioFromEvent =
              typeof parsed.share_ratio === "string"
                ? parsed.share_ratio
                : String(parsed.share_ratio);
          }
        }

        // Extract TotalUSDValueUpdated events (before and after)
        const totalUsdValueEvents = firstDryrunResult.events.filter((event) =>
          event.type.includes("TotalUSDValueUpdated"),
        );

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
      }

      // Extract balance changes
      if (firstDryrunResult.balanceChanges) {
        for (const balanceChange of firstDryrunResult.balanceChanges) {
          if (balanceChange.amount) {
            balanceChanges.push({
              coinType: balanceChange.coinType || "",
              amount: balanceChange.amount,
            });
          }
        }
      }

      // Calculate USD value withdrawn
      let usdValueWithdrawn: string | null = null;

      if (totalUsdValueBefore && totalUsdValueAfter) {
        const before = BigInt(totalUsdValueBefore);
        const after = BigInt(totalUsdValueAfter);
        const withdrawn = before - after;

        usdValueWithdrawn = withdrawn.toString();
      }

      if (!actualAmount) {
        throw new Error("Failed to extract amount from dryrun result");
      }

      // Step 2: Build transaction with actual amount (add some buffer for slippage)
      const actualAmountBigInt = BigInt(actualAmount);
      // Add 1% buffer for slippage protection
      const maxAmountReceived =
        (actualAmountBigInt * BigInt(101)) / BigInt(100);

      const finalTx = buildExecuteWithdrawTransaction(
        request,
        operatorCap,
        maxAmountReceived,
      );

      finalTx.setSender(currentAccount.address);

      // Step 3: Verify the final transaction can pass build without errors
      await finalTx.build({ client }).catch(extractBuildError);

      // Cache the final transaction for execution
      setCachedTransaction(finalTx);

      setDryrunResult({
        shares: actualShares || String(request.shares),
        shareRatio: shareRatioFromEvent || "",
        actualAmount: actualAmount || undefined,
        totalUsdValueBefore: totalUsdValueBefore || undefined,
        totalUsdValueAfter: totalUsdValueAfter || undefined,
        usdValueWithdrawn: usdValueWithdrawn || undefined,
        shareRatioFromEvent: shareRatioFromEvent || undefined,
        balanceChanges: balanceChanges.length > 0 ? balanceChanges : undefined,
        isLoading: false,
      });
    } catch (err) {
      setDryrunResult({
        shares: "",
        shareRatio: "",
        actualAmount: undefined,
        totalUsdValueBefore: undefined,
        totalUsdValueAfter: undefined,
        usdValueWithdrawn: undefined,
        shareRatioFromEvent: undefined,
        balanceChanges: undefined,
        isLoading: false,
        error:
          err instanceof Error ? err.message : String(err ?? "Unknown error"),
      });

      // Clear cached transaction on error
      setCachedTransaction(null);

      errorLog("Withdraw dryrun failed: %O", err);
    }
  };

  const handleClose = () => {
    setDryrunResult(null);
    setCachedTransaction(null);
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
        description: "You need an OperatorCap to execute withdraws",
        color: "danger",
      });

      return;
    }

    setIsExecuting(true);

    try {
      debugLog(
        "Executing withdraw - request_id:%s shares:%s expected_amount:%s",
        request.request_id,
        request.shares,
        request.expected_amount,
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
              description: "Withdraw executed successfully",
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
              "Execute withdraw failed",
            );
          },
        },
      );
    } catch (err) {
      setIsExecuting(false);

      errorLog("Execute withdraw hook error: %O", err);

      addToast({
        title: "Execute withdraw failed",
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
        <ModalHeader>Confirm Withdraw Execution</ModalHeader>
        <ModalBody>
          {request && (
            <div className="space-y-4">
              <div>
                <p className="text-sm text-default-500">Request ID</p>
                <p className="font-mono text-sm">{request.request_id}</p>
              </div>

              <div>
                <p className="text-sm text-default-500">Shares to Withdraw</p>
                <p className="font-medium">
                  {formatDecimal(String(request.shares), VAULT_DECIMALS, {
                    maximumFractionDigits: 9,
                  }) ?? "N/A"}{" "}
                  shares
                </p>
              </div>

              <div>
                <p className="text-sm text-default-500">Expected Amount</p>
                <p className="font-medium">
                  {formatCoinAmount(request.expected_amount, coinDecimals)}{" "}
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
                  {dryrunResult?.actualAmount && (
                    <div>
                      <p className="text-sm text-default-500">
                        Actual Amount (from dryrun)
                      </p>
                      <p className="font-mono text-sm font-medium">
                        {formatCoinAmount(
                          dryrunResult.actualAmount,
                          coinDecimals || 9,
                        )}{" "}
                        {vault.coin_type?.split("::").pop() || ""}
                      </p>
                    </div>
                  )}

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
                </>
              )}
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
