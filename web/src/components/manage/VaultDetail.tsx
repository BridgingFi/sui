import type { VaultInfo } from "@/lib/types";
import type { DepositRequest } from "@/hooks/useVaultRequests";

import {
  addToast,
  BreadcrumbItem,
  Breadcrumbs,
  Button,
  Card,
  CardBody,
  CardHeader,
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
import { useState } from "react";
import dayjs from "dayjs";

import {
  useDepositRequests,
  useWithdrawRequests,
} from "@/hooks/useVaultRequests";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { useVaultAssets } from "@/hooks/useVaultAssets";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";
import { parseTransactionError } from "@/utils/errorCodes";

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

    setExecutingRequestId(request.request_id);

    try {
      // Validate deposit request amount (defensive check to avoid wasting gas)
      if (BigInt(String(request.amount || 0)) === 0n) {
        throw new Error(
          "Deposit request amount is zero. Should not execute deposit with zero amount.",
        );
      }

      debugLog(
        "Executing deposit - request_id:%s amount:%s expected_shares:%s",
        request.request_id,
        request.amount,
        request.expected_shares,
      );

      const tx = new Transaction();

      // Extract coin type from vault coin_type
      const coinType = vault.coin_type;

      if (!coinType) {
        throw new Error("Coin type is missing from vault");
      }

      // Update principal value before execute_deposit because execute_deposit
      // calls get_total_usd_value_before (line 820) which requires all assets
      // to be updated within MAX_UPDATE_INTERVAL which is 0. execute_deposit
      // will update it again after joining the coin (line 839) to get the
      // accurate "after" value.
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
          tx.pure.u64(request.request_id),
          tx.pure.u256(maxSharesReceived.toString()),
        ],
      });

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: async () => {
            setExecutingRequestId(null);
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

      const errorMessage =
        err instanceof Error ? err.message : parseTransactionError(err);

      errorLog("Execute deposit failed: %O", err);
      addToast({
        title: "Transaction failed",
        description: errorMessage,
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

      const errorMessage =
        err instanceof Error ? err.message : parseTransactionError(err);

      errorLog("Cancel deposit failed: %O", err);
      addToast({
        title: "Transaction failed",
        description: errorMessage,
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
    </section>
  );
}
