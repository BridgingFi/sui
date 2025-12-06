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
  BreadcrumbItem,
  Breadcrumbs,
  Button,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Checkbox,
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
  Tooltip,
} from "@heroui/react";
import { useState } from "react";

import { AssetsValueList } from "@/components/manage/AssetsValueList";
import { CopyButton } from "@/components/common/CopyButton";
import { CreateBridgingFiPositionForm } from "@/components/manage/CreateBridgingFiPositionForm";
import { VAULT_DECIMALS } from "@/lib/constants";
import { isBridgingFiPosition } from "@/utils/bridgingfi";
import {
  useDepositRequests,
  useWithdrawRequests,
} from "@/hooks/useVaultRequests";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { loggers } from "@/utils/debug";
import {
  showTransactionErrorToast,
  extractTransactionErrorInfo,
} from "@/utils/transaction";

const { errorLog, debugLog } = loggers("app:manage:vault-detail");

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";
const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";

interface VaultDetailProps {
  vault: VaultInfo;
}

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

function formatAmount(amount: number, decimals: number = 6): string {
  return (amount / Math.pow(10, decimals)).toFixed(6);
}

function formatExpectedShares(shares: string): string {
  try {
    const bigIntShares = BigInt(shares);

    // Shares are pure numbers (no decimals), so no conversion needed
    const value = Number(bigIntShares);

    return value.toFixed(6);
  } catch {
    return shares;
  }
}

const PAGE_SIZE = 20;

/**
 * Manage vault detail component
 * Displays vault information and all deposit/withdraw requests with execute/cancel actions
 */
export function VaultDetail({ vault }: VaultDetailProps) {
  const currentAccount = useCurrentAccount();
  const { operatorCaps } = useOperatorCaps();
  const client = useSuiClient();

  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  // Query vault info
  const {
    freePrincipal,
    claimablePrincipal,
    assetTypes,
    isLoading: isLoadingVaultInfo,
  } = useVaultInfo(vault.vault_id);

  // Pagination state for deposit requests
  const [depositCursor, setDepositCursor] = useState<string | undefined>(
    undefined,
  );
  const [depositCursors, setDepositCursors] = useState<string[]>([]); // History of cursors for "previous page"

  // Pagination state for withdraw requests
  const [withdrawCursor, setWithdrawCursor] = useState<string | undefined>(
    undefined,
  );
  const [withdrawCursors, setWithdrawCursors] = useState<string[]>([]); // History of cursors for "previous page"

  const {
    data: depositRequestsData,
    isLoading: isLoadingDepositRequests,
    refetch: refetchDepositRequests,
  } = useDepositRequests(vault.vault_id, {
    limit: PAGE_SIZE,
    cursor: depositCursor,
  });

  const {
    data: withdrawRequestsData,
    isLoading: isLoadingWithdrawRequests,
    refetch: refetchWithdrawRequests,
  } = useWithdrawRequests(vault.vault_id, {
    limit: PAGE_SIZE,
    cursor: withdrawCursor,
  });

  // Ensure requests are always arrays
  const depositRequests = depositRequestsData?.requests || [];
  const withdrawRequests = withdrawRequestsData?.requests || [];

  // Handle deposit pagination
  const handleDepositNextPage = () => {
    if (depositRequestsData?.pagination.nextCursor) {
      setDepositCursors([...depositCursors, depositCursor || ""]);
      setDepositCursor(depositRequestsData.pagination.nextCursor);
    }
  };

  const handleDepositPreviousPage = () => {
    if (depositCursors.length > 0) {
      const newCursors = [...depositCursors];

      newCursors.pop();
      setDepositCursors(newCursors);

      setDepositCursor(
        newCursors.length > 0 ? newCursors[newCursors.length - 1] : undefined,
      );
    } else {
      setDepositCursor(undefined);
    }
  };

  // Handle withdraw pagination
  const handleWithdrawNextPage = () => {
    if (withdrawRequestsData?.pagination.nextCursor) {
      setWithdrawCursors([...withdrawCursors, withdrawCursor || ""]);
      setWithdrawCursor(withdrawRequestsData.pagination.nextCursor);
    }
  };

  const handleWithdrawPreviousPage = () => {
    if (withdrawCursors.length > 0) {
      const newCursors = [...withdrawCursors];

      newCursors.pop();
      setWithdrawCursors(newCursors);

      setWithdrawCursor(
        newCursors.length > 0 ? newCursors[newCursors.length - 1] : undefined,
      );
    } else {
      setWithdrawCursor(undefined);
    }
  };

  const refetchRequests = () => {
    refetchDepositRequests();
    refetchWithdrawRequests();
  };

  const [executingRequestId, setExecutingRequestId] = useState<
    string | number | null
  >(null);
  const [cancellingRequestId, setCancellingRequestId] = useState<
    string | number | null
  >(null);

  // Confirmation dialog state
  const [confirmDialogOpen, setConfirmDialogOpen] = useState(false);
  const [pendingRequest, setPendingRequest] = useState<DepositRequest | null>(
    null,
  );
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
  // Cache the transaction built for dryrun to ensure consistency with execution
  const [cachedTransaction, setCachedTransaction] =
    useState<Transaction | null>(null);

  // Create position modal state
  const [isCreatePositionModalOpen, setIsCreatePositionModalOpen] =
    useState(false);

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

    // TODO: Future implementation - Update Switchboard aggregator prices if
    // updateSwitchboardPrice is true
    //
    // This will require:
    // 1. Get all aggregator IDs from OracleConfig
    // 2. Use Switchboard SDK's fetchUpdateTx to get oracle updates
    // 3. Add aggregator_submit_result_action::run calls to transaction
    // 4. Re-run dryrun to update confirmation dialog with new results

    // TODO: Future implementation - Update OracleConfig prices if
    // updateOraclePrice is true
    //
    // This will require:
    // 1. After Switchboard updates, call update_price for each asset type
    // 2. Re-run dryrun to update confirmation dialog with new results

    // TODO: Future implementation - Update all asset types before and after
    // execute_deposit
    //
    // Only update_free_principal_value is called externally before
    // execute_deposit and internally by execute_deposit after joining the
    // coin (line 839). However, other asset types (coin_type assets, Defi
    // positions) are not updated. Future implementation may need to update
    // all asset types before and after execute_deposit.
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

  const handleExecuteDeposit = async (request: DepositRequest) => {
    if (!currentAccount) {
      addToast({
        title: "Wallet not connected",
        color: "danger",
      });

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

    // Set pending request and show confirmation dialog
    setPendingRequest(request);
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
    setConfirmDialogOpen(true);

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

      // Build the transaction for dryrun and we can catch errors in advance as
      // there's an internal dryrun but unfortunately we can not get dryrun
      // result from build.
      const firstTxBytes = await firstTx.build({ client }).catch((e) => {
        // Try to get explained error message
        const { errorMessage: extractedErrorMessage } =
          extractTransactionErrorInfo(e);

        // Throw new error with explained message, or original error if no explanation
        throw extractedErrorMessage
          ? new Error(
              `${extractedErrorMessage} - ${
                e instanceof Error ? e.message : String(e)
              }`,
            )
          : e;
      });

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
        // The first one is before deposit, the last one is after deposit
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
      // This matches Move logic: if total_shares == 0, return vault_utils::to_decimals(1)
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
      await finalTx.build({ client }).catch((e) => {
        const { errorMessage: extractedErrorMessage } =
          extractTransactionErrorInfo(e);

        throw extractedErrorMessage
          ? new Error(
              `${extractedErrorMessage} - ${
                e instanceof Error ? e.message : String(e)
              }`,
            )
          : e;
      });

      // Step 4: Calculate values from events and simulate shares

      // Calculate USD value deposited from events
      let usdValueDeposited: string | null = null;

      if (totalUsdValueBefore && totalUsdValueAfter) {
        const before = BigInt(totalUsdValueBefore);
        const after = BigInt(totalUsdValueAfter);
        const deposited = after - before;

        usdValueDeposited = deposited.toString();
      }

      // Simulate shares using share_ratio_before from event
      // Following Move logic: user_shares = vault_utils::div_d(new_usd_value_deposited, share_ratio_before)
      // where div_d(v1, v2) = v1 * DECIMALS / v2
      let simulatedShares: string | null = null;
      let sharesDifference: string | null = null;

      if (shareRatioBefore && usdValueDeposited) {
        const usdValueDepositedBigInt = BigInt(usdValueDeposited);
        const shareRatioBeforeBigInt = BigInt(shareRatioBefore);

        // Simulate: shares = div_d(usdValueDeposited, shareRatioBefore)
        // = usdValueDeposited * DECIMALS / shareRatioBefore
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

      // Use share_ratio_before for display (more accurate than estimated)
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

  const handleConfirmExecute = async () => {
    if (!pendingRequest || !currentAccount) {
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

    setConfirmDialogOpen(false);
    setExecutingRequestId(pendingRequest.request_id);

    try {
      debugLog(
        "Executing deposit - request_id:%s amount:%s expected_shares:%s",
        pendingRequest.request_id,
        pendingRequest.amount,
        pendingRequest.expected_shares,
      );

      // Use cached transaction from dryrun to ensure consistency
      // If cache is missing (shouldn't happen), rebuild it
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
            setExecutingRequestId(null);
            setPendingRequest(null);
            setDryrunResult(null);
            setCachedTransaction(null);
            addToast({
              title: "Success",
              description: "Deposit executed successfully",
              color: "success",
            });
            // Wait a bit for events to be indexed
            setTimeout(() => {
              refetchRequests();
            }, 2000);
          },
          onError: (err) => {
            setExecutingRequestId(null);
            setPendingRequest(null);
            setDryrunResult(null);
            setCachedTransaction(null);
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
      setExecutingRequestId(null);
      setPendingRequest(null);
      setDryrunResult(null);
      setCachedTransaction(null);

      errorLog("Execute deposit hook error: %O", err);

      addToast({
        title: "Execute deposit failed",
        description:
          err instanceof Error ? err.message : String(err ?? "Unknown error"),
        color: "danger",
      });
    }
  };

  const handleCancelDeposit = async (request: DepositRequest) => {
    if (!currentAccount) {
      addToast({
        title: "Wallet not connected",
        color: "danger",
      });

      return;
    }

    // Get first available OperatorCap
    const operatorCap = operatorCaps?.[0];

    if (!operatorCap) {
      addToast({
        title: "No OperatorCap found",
        description: "You need an OperatorCap to cancel deposits",
        color: "danger",
      });

      return;
    }

    // Validate request data
    if (!request.request_id || !request.receipt_id || !request.recipient) {
      addToast({
        title: "Invalid request data",
        description: "Request ID, receipt ID, or recipient is missing",
        color: "danger",
      });

      return;
    }

    setCancellingRequestId(request.request_id);

    try {
      const tx = new Transaction();

      // Extract coin type from vault coin_type
      const coinType = vault.coin_type;

      if (!coinType) {
        throw new Error("Coin type is missing from vault");
      }

      // Call cancel_user_deposit
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::cancel_user_deposit`,
        typeArguments: [coinType],
        arguments: [
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          tx.object(vault.vault_id),
          tx.pure.u64(request.request_id),
          tx.pure.address(request.receipt_id),
          tx.pure.address(request.recipient),
          tx.object(SUI_CLOCK_OBJECT_ID),
        ],
      });

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setCancellingRequestId(null);
            addToast({
              title: "Success",
              description: "Deposit canceled successfully",
              color: "success",
            });
            // Wait a bit for events to be indexed
            setTimeout(() => {
              refetchRequests();
            }, 2000);
          },
          onError: (err) => {
            setCancellingRequestId(null);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Cancel deposit failed",
            );
          },
        },
      );
    } catch (err) {
      setCancellingRequestId(null);
      errorLog("Cancel deposit hook error: %O", err);

      addToast({
        title: "Cancel deposit failed",
        description:
          err instanceof Error ? err.message : String(err ?? "Unknown error"),
        color: "danger",
      });
    }
  };

  return (
    <section className="space-y-8">
      <header className="space-y-2">
        <Breadcrumbs>
          <BreadcrumbItem href="/manage">Vaults</BreadcrumbItem>
          <BreadcrumbItem>
            <div className="flex items-center">
              <Tooltip content={vault.vault_id}>
                <span>{truncateAddress(vault.vault_id)}</span>
              </Tooltip>
              <CopyButton disableTooltip value={vault.vault_id} />
            </div>
          </BreadcrumbItem>
        </Breadcrumbs>
        <div className="flex items-center gap-4 flex-wrap">
          <p className="text-default-500">
            Coin Type:{" "}
            <span className="text-foreground">
              {vault.coin_type.split("::").pop() || vault.coin_type}
            </span>
          </p>
          {!isLoadingVaultInfo && (
            <>
              <p className="text-default-500">
                Free Principal:{" "}
                <span className="text-foreground font-mono">
                  {freePrincipal !== null
                    ? formatAmount(Number(freePrincipal))
                    : "N/A"}
                </span>
              </p>
              <p className="text-default-500">
                Claimable Principal:{" "}
                <span className="text-foreground font-mono">
                  {claimablePrincipal !== null
                    ? formatAmount(Number(claimablePrincipal))
                    : "N/A"}
                </span>
              </p>
            </>
          )}
        </div>
      </header>

      {/* Assets Value Information */}
      <AssetsValueList
        assetTypes={assetTypes}
        vault={vault}
        onCreatePosition={() => setIsCreatePositionModalOpen(true)}
      />

      {/* Deposit Requests */}
      <Card>
        <CardHeader>
          Deposit Requests
          <span className="text-sm text-default-500 ml-auto">
            {depositRequests.length} requests
            {depositCursor && " (page)"}
          </span>
        </CardHeader>
        <Divider />
        <CardBody className="p-0">
          {isLoadingDepositRequests ? (
            <div className="flex items-center justify-center py-8 px-4">
              <Spinner size="lg" />
              <p className="ml-4 text-default-500">
                Loading deposit requests...
              </p>
            </div>
          ) : depositRequests.length === 0 ? (
            <div className="text-center py-8 px-4 text-default-500">
              <p>No active deposit requests.</p>
            </div>
          ) : (
            <>
              <Table
                aria-label="Deposit requests"
                classNames={{
                  wrapper: ["p-0", "rounded-none"],
                  th: ["first:rounded-s-none", "last:rounded-e-none"],
                }}
              >
                <TableHeader>
                  <TableColumn>REQUEST ID</TableColumn>
                  <TableColumn>RECEIPT ID</TableColumn>
                  <TableColumn>RECIPIENT</TableColumn>
                  <TableColumn>AMOUNT</TableColumn>
                  <TableColumn>EXPECTED SHARES</TableColumn>
                  <TableColumn>ACTIONS</TableColumn>
                </TableHeader>
                <TableBody>
                  {depositRequests.map((item) => (
                    <TableRow key={item.request_id}>
                      <TableCell>
                        <code className="text-xs">{item.request_id}</code>
                      </TableCell>
                      <TableCell>
                        <code className="text-xs">
                          {truncateAddress(item.receipt_id)}
                        </code>
                      </TableCell>
                      <TableCell>
                        <code className="text-xs">
                          {truncateAddress(item.recipient)}
                        </code>
                      </TableCell>
                      <TableCell>
                        <span className="font-medium">
                          {formatAmount(Number(item.amount))}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="font-mono text-sm">
                          {formatExpectedShares(String(item.expected_shares))}
                        </span>
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-2">
                          <Button
                            color="primary"
                            isDisabled={
                              isPending ||
                              executingRequestId === item.request_id ||
                              cancellingRequestId === item.request_id
                            }
                            isLoading={executingRequestId === item.request_id}
                            size="sm"
                            onPress={() => handleExecuteDeposit(item)}
                          >
                            Execute
                          </Button>
                          <Button
                            color="danger"
                            isDisabled={
                              isPending ||
                              executingRequestId === item.request_id ||
                              cancellingRequestId === item.request_id
                            }
                            isLoading={cancellingRequestId === item.request_id}
                            size="sm"
                            variant="light"
                            onPress={() => handleCancelDeposit(item)}
                          >
                            Cancel
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              {/* Pagination controls */}
              <div className="flex items-center justify-between mt-4 pt-4 border-t border-default-200">
                <Button
                  isDisabled={depositCursors.length === 0 && !depositCursor}
                  size="sm"
                  variant="light"
                  onPress={handleDepositPreviousPage}
                >
                  Previous
                </Button>
                <span className="text-sm text-default-500">
                  Page {depositCursors.length + 1}
                </span>
                <Button
                  isDisabled={!depositRequestsData?.pagination.hasNextPage}
                  size="sm"
                  variant="light"
                  onPress={handleDepositNextPage}
                >
                  Next
                </Button>
              </div>
            </>
          )}
        </CardBody>
      </Card>

      {/* Withdraw Requests */}
      <Card>
        <CardHeader>
          Withdraw Requests
          <span className="text-sm text-default-500 ml-auto">
            {withdrawRequests.length} requests
            {withdrawCursor && " (page)"}
          </span>
        </CardHeader>
        <Divider />
        <CardBody className="p-0">
          {isLoadingWithdrawRequests ? (
            <div className="flex items-center justify-center py-8 px-4">
              <Spinner size="lg" />
              <p className="ml-4 text-default-500">
                Loading withdraw requests...
              </p>
            </div>
          ) : withdrawRequests.length === 0 ? (
            <div className="text-center py-8 px-4 text-default-500">
              <p>No active withdraw requests.</p>
            </div>
          ) : (
            <>
              <Table
                aria-label="Withdraw requests"
                classNames={{
                  wrapper: ["p-0", "rounded-none"],
                  th: ["first:rounded-s-none", "last:rounded-e-none"],
                }}
              >
                <TableHeader>
                  <TableColumn>REQUEST ID</TableColumn>
                  <TableColumn>RECEIPT ID</TableColumn>
                  <TableColumn>RECIPIENT</TableColumn>
                  <TableColumn>SHARES</TableColumn>
                  <TableColumn>EXPECTED AMOUNT</TableColumn>
                </TableHeader>
                <TableBody>
                  {withdrawRequests.map((item) => (
                    <TableRow key={item.request_id}>
                      <TableCell>
                        <code className="text-xs">{item.request_id}</code>
                      </TableCell>
                      <TableCell>
                        <code className="text-xs">
                          {truncateAddress(item.receipt_id)}
                        </code>
                      </TableCell>
                      <TableCell>
                        <code className="text-xs">
                          {truncateAddress(item.recipient)}
                        </code>
                      </TableCell>
                      <TableCell>
                        <span className="font-mono text-sm">
                          {formatExpectedShares(String(item.shares))}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="font-medium">
                          {formatAmount(Number(item.expected_amount))}
                        </span>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              {/* Pagination controls */}
              <div className="flex items-center justify-between mt-4 pt-4 border-t border-default-200">
                <Button
                  isDisabled={withdrawCursors.length === 0 && !withdrawCursor}
                  size="sm"
                  variant="light"
                  onPress={handleWithdrawPreviousPage}
                >
                  Previous
                </Button>
                <span className="text-sm text-default-500">
                  Page {withdrawCursors.length + 1}
                </span>
                <Button
                  isDisabled={!withdrawRequestsData?.pagination.hasNextPage}
                  size="sm"
                  variant="light"
                  onPress={handleWithdrawNextPage}
                >
                  Next
                </Button>
              </div>
            </>
          )}
        </CardBody>
      </Card>

      {/* Execute Deposit Confirmation Dialog */}
      <Modal
        isOpen={confirmDialogOpen}
        scrollBehavior="inside"
        size="lg"
        onClose={() => {
          setConfirmDialogOpen(false);
          setPendingRequest(null);
          setDryrunResult(null);
        }}
      >
        <ModalContent>
          <ModalHeader>Confirm Deposit Execution</ModalHeader>
          <ModalBody>
            {pendingRequest && (
              <div className="space-y-4">
                <div>
                  <p className="text-sm text-default-500">Request ID</p>
                  <p className="font-mono text-sm">
                    {pendingRequest.request_id}
                  </p>
                </div>

                <div>
                  <p className="text-sm text-default-500">Deposit Amount</p>
                  <p className="font-medium">
                    {formatAmount(Number(pendingRequest.amount))}{" "}
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
                      <p className="text-sm text-danger">
                        {dryrunResult.error}
                      </p>
                    </div>
                  </div>
                ) : (
                  <>
                    <div>
                      <p className="text-sm text-default-500">
                        Expected Shares (from request)
                      </p>
                      <p className="font-mono text-sm">
                        {formatExpectedShares(
                          String(pendingRequest.expected_shares),
                        )}
                      </p>
                    </div>

                    {dryrunResult?.shares && (
                      <div>
                        <p className="text-sm text-default-500">
                          Actual Shares (from dryrun)
                        </p>
                        <p className="font-mono text-sm font-medium">
                          {formatExpectedShares(dryrunResult.shares)}
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
                                {formatAmount(
                                  Number(dryrunResult.totalUsdValueBefore),
                                  9,
                                )}
                              </span>
                            </div>
                            <div className="flex justify-between">
                              <span className="text-default-500">After:</span>
                              <span className="font-mono">
                                {formatAmount(
                                  Number(dryrunResult.totalUsdValueAfter),
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
                                  {formatAmount(
                                    Number(dryrunResult.usdValueDeposited),
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
                          {formatAmount(
                            Number(dryrunResult.shareRatioFromEvent),
                            9,
                          )}
                        </p>
                      </div>
                    )}

                    {dryrunResult?.simulatedShares && (
                      <div>
                        <p className="text-sm text-default-500">
                          Simulated Shares (calculated from events)
                        </p>
                        <p className="font-mono text-sm">
                          {formatExpectedShares(dryrunResult.simulatedShares)}
                        </p>
                        <p className="text-xs text-default-400">
                          Calculated: (usdValueDeposited × DECIMALS) /
                          shareRatio
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
                              ? `+${formatExpectedShares(
                                  dryrunResult.sharesDifference,
                                )} (Actual higher)`
                              : `${formatExpectedShares(
                                  dryrunResult.sharesDifference,
                                )} (Actual lower)`}
                        </p>
                      </div>
                    )}
                  </>
                )}

                <div className="border-t pt-4 space-y-2">
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
                        {/* TODO: Future implementation - When enabled, this will:
                        1. Fetch all aggregator IDs from OracleConfig
                        2. Use Switchboard SDK's fetchUpdateTx to get oracle updates
                        3. Add aggregator_submit_result_action::run calls to transaction
                        4. Re-run dryrun to update confirmation dialog with new results */}
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
                        {/* TODO: Future implementation - When enabled, this will:
                        1. After Switchboard updates, call update_price for each asset type
                        2. Re-run dryrun to update confirmation dialog with new results */}
                        Future: Update OracleConfig prices from aggregators
                      </p>
                    </div>
                  </Checkbox>
                </div>
              </div>
            )}
          </ModalBody>
          <ModalFooter>
            <Button
              variant="light"
              onPress={() => {
                setConfirmDialogOpen(false);
                setPendingRequest(null);
                setDryrunResult(null);
                setCachedTransaction(null);
              }}
            >
              Cancel
            </Button>
            <Button
              color="primary"
              isDisabled={
                dryrunResult?.isLoading ||
                !!dryrunResult?.error ||
                !pendingRequest
              }
              onPress={handleConfirmExecute}
            >
              Confirm & Execute
            </Button>
          </ModalFooter>
        </ModalContent>
      </Modal>

      {/* Create Position Modal */}
      <CreateBridgingFiPositionForm
        isOpen={isCreatePositionModalOpen}
        vault={vault}
        onClose={() => setIsCreatePositionModalOpen(false)}
        onSuccess={() => {
          // Refetch position data after successful creation
          // The useBridgingFiPosition hook will automatically refetch
        }}
      />
    </section>
  );
}
