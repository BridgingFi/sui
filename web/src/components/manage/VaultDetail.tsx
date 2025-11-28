import type { VaultInfo } from "@/lib/types";
import type { DepositRequest } from "@/hooks/useVaultRequests";
import type { DryRunTransactionBlockResponse } from "@mysten/sui/jsonRpc";

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
} from "@heroui/react";
import { useState } from "react";
import dayjs from "dayjs";

import {
  useDepositRequests,
  useWithdrawRequests,
} from "@/hooks/useVaultRequests";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { useVaultAssets } from "@/hooks/useVaultAssets";
import { useOracleConfig } from "@/hooks/useOracleConfig";
import { loggers } from "@/utils/debug";
import {
  showTransactionErrorToast,
  extractTransactionErrorInfo,
} from "@/utils/transaction";
import { ALL_ERROR_CODES } from "@/utils/errorCodes";

const { errorLog, debugLog } = loggers("app:manage:vault-detail");

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";
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

    // Assuming shares use 9 decimals (same as DECIMALS in vault_utils)
    const decimals = BigInt(1e9);
    const value = Number(bigIntShares) / Number(decimals);

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
  const { oracleConfig } = useOracleConfig();

  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  // Query vault info
  const {
    freePrincipal,
    claimablePrincipal,
    assetTypes,
    isLoading: isLoadingVaultInfo,
  } = useVaultInfo(vault.vault_id);

  // Query vault assets
  const { assets, isLoading: isLoadingAssets } = useVaultAssets(
    vault.vault_id,
    assetTypes || [],
  );

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
    oraclePrice: string;
    isLoading: boolean;
    error?: string;
    errorCode?: number;
    errorDetails?: string;
  } | null>(null);
  const [updateSwitchboardPrice, setUpdateSwitchboardPrice] = useState(false);
  const [updateOraclePrice, setUpdateOraclePrice] = useState(false);
  // Cache the transaction built for dryrun to ensure consistency with execution
  const [cachedTransaction, setCachedTransaction] =
    useState<Transaction | null>(null);

  // Build transaction for execute_deposit (used for both dryrun and execution)
  const buildExecuteDepositTransaction = (
    request: DepositRequest,
    operatorCap: { objectId: string },
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
      target: `${VOLO_VAULT_PACKAGE_ID}::vault::update_free_principal_value`,
      typeArguments: [coinType],
      arguments: [
        tx.object(vault.vault_id),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    // Call execute_deposit
    // Note: max_shares_received should be calculated based on current vault state
    // For now, we'll use expected_shares * 1.1 (10% slippage tolerance)
    const expectedSharesBigInt = BigInt(request.expected_shares);
    const maxSharesReceived =
      (expectedSharesBigInt * BigInt(110)) / BigInt(100); // 10% slippage

    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID}::operation::execute_deposit`,
      typeArguments: [coinType],
      arguments: [
        tx.object(VOLO_OPERATION_ID),
        tx.object(operatorCap.objectId),
        tx.object(vault.vault_id),
        tx.object(vault.reward_manager_id),
        tx.object(SUI_CLOCK_OBJECT_ID),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.pure.u64(String(request.request_id)),
        tx.pure.u256(maxSharesReceived.toString()),
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
    setDryrunResult({ shares: "", oraclePrice: "", isLoading: true });
    setConfirmDialogOpen(true);

    // Perform dryrun to get simulation results
    try {
      // Build transaction using the same function that will be used for execution
      const tx = buildExecuteDepositTransaction(request, operatorCap);

      // Set sender for dryrun (required for dryRunTransactionBlock)
      tx.setSender(currentAccount.address);

      // Get oracle price for the coin type
      let oraclePrice = "0";

      if (oracleConfig) {
        const priceInfo = oracleConfig.aggregators.get(vault.coin_type || "");

        if (priceInfo) {
          oraclePrice = priceInfo.price;
        }
      }

      // Perform dryrun to get actual shares
      // Note: tx.build() internally calls resolveTransactionPlugin which calls dryRunTransactionBlock
      // We can extract dryrun result from build error's cause if build fails
      let actualShares: string | null = null;

      await tx.build({ client }).catch((e) => {
        // Extract error info from build error (only works for errors with error.cause)
        const { errorMessage: extractedErrorMessage } =
          extractTransactionErrorInfo(e);

        // Try to extract dryrun result from error.cause to get shares
        if (e instanceof Error && "cause" in e && e.cause) {
          const cause = e.cause as DryRunTransactionBlockResponse;

          // Check if this is a DryRunTransactionBlockResponse and extract shares
          if (cause.effects && cause.events !== undefined) {
            if (cause.effects?.status?.status === "success" && cause.events) {
              const depositEvent = cause.events.find((event) =>
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
            }
          }
        }

        // Throw new error with extracted message, or original error if no extraction
        // Error logging will be handled by outer catch
        throw extractedErrorMessage
          ? new Error(
              `${extractedErrorMessage} - ${
                e instanceof Error ? e.message : String(e)
              }`,
            )
          : e;
      });

      // Cache the transaction after successful build to ensure execution uses the same one
      setCachedTransaction(tx);

      setDryrunResult({
        shares: actualShares || "",
        oraclePrice,
        isLoading: false,
      });
    } catch (err) {
      // Handle common errors (build errors are already processed above)
      // JsonRpcError from dryRunTransactionBlock is already re-thrown as regular Error above
      const errorMessage =
        err instanceof Error ? err.message : String(err ?? "Unknown error");
      const errorDetails = err instanceof Error ? String(err) : errorMessage;

      setDryrunResult({
        shares: "",
        oraclePrice: "",
        isLoading: false,
        error: errorMessage,
        errorDetails: errorDetails || errorMessage,
      });

      // Clear cached transaction on error
      setCachedTransaction(null);

      // Log full error details for admin debugging
      errorLog("Dryrun failed - Error: %s, Details: %O", errorMessage, err);
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
        debugLog(
          "Cached transaction not found, rebuilding (this should not happen)",
        );
        tx = buildExecuteDepositTransaction(pendingRequest, operatorCap);
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
        target: `${VOLO_VAULT_PACKAGE_ID}::operation::cancel_user_deposit`,
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
          <BreadcrumbItem href="/manage">Manage</BreadcrumbItem>
          <BreadcrumbItem>
            Vault ({truncateAddress(vault.vault_id)})
          </BreadcrumbItem>
        </Breadcrumbs>
        <p className="text-default-500">
          Coin Type: {vault.coin_type.split("::").pop() || vault.coin_type}
        </p>
      </header>

      {/* Vault Information */}
      <Card>
        <CardHeader>
          <h2 className="text-lg font-medium">Vault Information</h2>
        </CardHeader>
        <CardBody className="space-y-4">
          {isLoadingVaultInfo ? (
            <div className="flex items-center gap-2">
              <Spinner size="sm" />
              <span className="text-sm text-default-500">Loading...</span>
            </div>
          ) : (
            <>
              <div>
                <p className="text-sm text-default-500">Free Principal</p>
                <p className="font-medium font-mono">
                  {freePrincipal !== null
                    ? formatAmount(Number(freePrincipal))
                    : "N/A"}
                </p>
              </div>
              <div>
                <p className="text-sm text-default-500">Claimable Principal</p>
                <p className="font-medium font-mono">
                  {claimablePrincipal !== null
                    ? formatAmount(Number(claimablePrincipal))
                    : "N/A"}
                </p>
              </div>
            </>
          )}
        </CardBody>
      </Card>

      {/* Assets Value Information */}
      {assetTypes && assetTypes.length > 0 && (
        <Card>
          <CardHeader>
            <h2 className="text-lg font-medium">Assets Value</h2>
          </CardHeader>
          <CardBody>
            {isLoadingAssets ? (
              <div className="flex items-center gap-2">
                <Spinner size="sm" />
                <span className="text-sm text-default-500">Loading...</span>
              </div>
            ) : assets.length === 0 ? (
              <div className="text-center py-4 text-default-500">
                <p>No assets found.</p>
              </div>
            ) : (
              <Table aria-label="Assets value">
                <TableHeader>
                  <TableColumn>ASSET TYPE</TableColumn>
                  <TableColumn>USD VALUE</TableColumn>
                  <TableColumn>LAST UPDATED</TableColumn>
                </TableHeader>
                <TableBody>
                  {assets.map((asset) => (
                    <TableRow key={asset.assetType}>
                      <TableCell>
                        <code className="text-xs">{asset.assetType}</code>
                      </TableCell>
                      <TableCell>
                        <span className="font-mono text-sm">
                          {asset.usdValue.toString()}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="text-sm">
                          {asset.lastUpdated > 0
                            ? dayjs(asset.lastUpdated).format(
                                "YYYY-MM-DD HH:mm:ss",
                              )
                            : "Never"}
                        </span>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardBody>
        </Card>
      )}

      {/* Deposit Requests */}
      <Card>
        <CardHeader>
          <h2 className="text-lg font-medium">Deposit Requests</h2>
          <span className="text-sm text-default-500 ml-auto">
            {depositRequests.length} requests
            {depositCursor && " (page)"}
          </span>
        </CardHeader>
        <CardBody>
          {isLoadingDepositRequests ? (
            <div className="flex items-center justify-center py-8">
              <Spinner size="lg" />
              <p className="ml-4 text-default-500">
                Loading deposit requests...
              </p>
            </div>
          ) : depositRequests.length === 0 ? (
            <div className="text-center py-8 text-default-500">
              <p>No active deposit requests.</p>
            </div>
          ) : (
            <>
              <Table aria-label="Deposit requests">
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
          <h2 className="text-lg font-medium">Withdraw Requests</h2>
          <span className="text-sm text-default-500 ml-auto">
            {withdrawRequests.length} requests
            {withdrawCursor && " (page)"}
          </span>
        </CardHeader>
        <CardBody>
          {isLoadingWithdrawRequests ? (
            <div className="flex items-center justify-center py-8">
              <Spinner size="lg" />
              <p className="ml-4 text-default-500">
                Loading withdraw requests...
              </p>
            </div>
          ) : withdrawRequests.length === 0 ? (
            <div className="text-center py-8 text-default-500">
              <p>No active withdraw requests.</p>
            </div>
          ) : (
            <>
              <Table aria-label="Withdraw requests">
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
                    {dryrunResult.errorCode && (
                      <div>
                        <p className="text-xs font-medium text-danger-700">
                          Error Code: {dryrunResult.errorCode}
                        </p>
                        <p className="text-xs text-danger-600">
                          {ALL_ERROR_CODES[dryrunResult.errorCode] ||
                            "Unknown error code"}
                        </p>
                      </div>
                    )}
                    {dryrunResult.errorDetails &&
                      dryrunResult.errorDetails !== dryrunResult.error && (
                        <details className="mt-2">
                          <summary className="cursor-pointer text-xs text-danger-700">
                            Show full error details (for admin debugging)
                          </summary>
                          <pre className="mt-2 max-h-40 overflow-auto rounded bg-danger-100 p-2 text-xs text-danger-900">
                            {dryrunResult.errorDetails}
                          </pre>
                        </details>
                      )}
                  </div>
                ) : (
                  <>
                    <div>
                      <p className="text-sm text-default-500">
                        Oracle Price (from OracleConfig)
                      </p>
                      <p className="font-medium">
                        {dryrunResult?.oraclePrice
                          ? formatAmount(Number(dryrunResult.oraclePrice), 9)
                          : "N/A"}
                      </p>
                    </div>

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

                    {dryrunResult?.shares ? (
                      <div>
                        <p className="text-sm text-default-500">
                          Simulated Shares (from dryrun)
                        </p>
                        <p className="font-mono text-sm font-medium">
                          {formatExpectedShares(dryrunResult.shares)}
                        </p>
                      </div>
                    ) : (
                      <div>
                        <p className="text-sm text-default-500">
                          Simulated Shares (from dryrun)
                        </p>
                        <p className="text-sm text-default-400 italic">
                          N/A (not available from simulation)
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
    </section>
  );
}
