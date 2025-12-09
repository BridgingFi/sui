import type { VaultInfo } from "@/lib/types";
import type { DepositRequest, WithdrawRequest } from "@/hooks/useVaultRequests";

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
import { ExecuteDepositModal } from "@/components/manage/ExecuteDepositModal";
import { ExecuteWithdrawModal } from "@/components/manage/ExecuteWithdrawModal";
import {
  formatCoinAmount,
  formatDecimal,
  truncateCoinType,
} from "@/utils/format";
import { VAULT_DECIMALS } from "@/lib/constants";
import {
  useDepositRequests,
  useWithdrawRequests,
} from "@/hooks/useVaultRequests";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { useCoinDecimals } from "@/hooks/useCoinDecimals";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";

const { errorLog } = loggers("app:manage:vault-detail");

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";

interface VaultDetailProps {
  vault: VaultInfo;
}

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
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

  // Get coin decimals from oracle config
  const coinDecimals = useCoinDecimals(vault.coin_type);

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

  const [cancellingRequestId, setCancellingRequestId] = useState<
    string | number | null
  >(null);
  const [cancellingWithdrawRequestId, setCancellingWithdrawRequestId] =
    useState<string | number | null>(null);

  // Execute modal state
  const [pendingDepositRequest, setPendingDepositRequest] =
    useState<DepositRequest | null>(null);
  const [pendingWithdrawRequest, setPendingWithdrawRequest] =
    useState<WithdrawRequest | null>(null);

  // Create position modal state
  const [isCreatePositionModalOpen, setIsCreatePositionModalOpen] =
    useState(false);

  const handleExecuteDeposit = (request: DepositRequest) => {
    setPendingDepositRequest(request);
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
          onError: (err: unknown) => {
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

  const handleExecuteWithdraw = (request: WithdrawRequest) => {
    setPendingWithdrawRequest(request);
  };

  const handleCancelWithdraw = async (request: WithdrawRequest) => {
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
        description: "You need an OperatorCap to cancel withdraws",
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

    setCancellingWithdrawRequestId(request.request_id);

    try {
      const tx = new Transaction();

      // Extract coin type from vault coin_type
      const coinType = vault.coin_type;

      if (!coinType) {
        throw new Error("Coin type is missing from vault");
      }

      // Call cancel_user_withdraw
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::cancel_user_withdraw`,
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
            setCancellingWithdrawRequestId(null);
            addToast({
              title: "Success",
              description: "Withdraw canceled successfully",
              color: "success",
            });
            // Wait a bit for events to be indexed
            setTimeout(() => {
              refetchRequests();
            }, 2000);
          },
          onError: (err: unknown) => {
            setCancellingWithdrawRequestId(null);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Cancel withdraw failed",
            );
          },
        },
      );
    } catch (err) {
      setCancellingWithdrawRequestId(null);
      errorLog("Cancel withdraw hook error: %O", err);

      addToast({
        title: "Cancel withdraw failed",
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
        <h1 className="text-3xl font-semibold">
          {vault.coin_type.split("::").pop() || "Vault"} Vault
        </h1>
        <div className="flex flex-wrap items-center gap-4 text-sm text-default-500">
          <div className="flex items-center">
            <Tooltip content={vault.coin_type}>
              <span>Coin Type: {truncateCoinType(vault.coin_type)}</span>
            </Tooltip>
            <CopyButton disableTooltip value={vault.coin_type} />
          </div>
          <span>
            Creator: {vault.creator.slice(0, 8)}...{vault.creator.slice(-6)}
          </span>
          <span>Created: {new Date(vault.created_at_ms).toLocaleString()}</span>
        </div>
        {!isLoadingVaultInfo && (
          <div className="flex flex-wrap items-center gap-4 text-sm text-default-500">
            <span>
              Free Principal:{" "}
              <span className="font-mono text-foreground">
                {formatCoinAmount(freePrincipal, coinDecimals)}
              </span>
            </span>
            <span>
              Claimable Principal:{" "}
              <span className="font-mono text-foreground">
                {formatCoinAmount(claimablePrincipal, coinDecimals)}
              </span>
            </span>
          </div>
        )}
      </header>

      {/* Assets Value Information */}
      <AssetsValueList
        assetTypes={assetTypes}
        coinType={vault.coin_type}
        vaultId={vault.vault_id}
        onCreatePosition={() => setIsCreatePositionModalOpen(true)}
      />

      {/* Deposit Requests */}
      <Card>
        <CardHeader>
          Deposit Requests
          <span className="ml-auto text-sm text-default-500">
            {depositRequests.length} requests
            {depositCursor && " (page)"}
          </span>
        </CardHeader>
        <Divider />
        <CardBody className="p-0">
          {isLoadingDepositRequests ? (
            <div className="flex items-center justify-center px-4 py-8">
              <Spinner size="lg" />
              <p className="ml-4 text-default-500">
                Loading deposit requests...
              </p>
            </div>
          ) : depositRequests.length === 0 ? (
            <div className="px-4 py-8 text-center text-default-500">
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
                          {formatCoinAmount(item.amount, coinDecimals)}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="font-mono text-sm">
                          {formatDecimal(
                            String(item.expected_shares),
                            VAULT_DECIMALS,
                            {
                              maximumFractionDigits: 9,
                            },
                          ) ?? "N/A"}
                        </span>
                      </TableCell>
                      <TableCell>
                        <div className="flex gap-2">
                          <Button
                            color="primary"
                            isDisabled={
                              isPending ||
                              cancellingRequestId === item.request_id
                            }
                            size="sm"
                            onPress={() => handleExecuteDeposit(item)}
                          >
                            Execute
                          </Button>
                          <Button
                            color="danger"
                            isDisabled={
                              isPending ||
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
              <div className="mt-4 flex items-center justify-between border-t border-default-200 pt-4">
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
          <span className="ml-auto text-sm text-default-500">
            {withdrawRequests.length} requests
            {withdrawCursor && " (page)"}
          </span>
        </CardHeader>
        <Divider />
        <CardBody className="p-0">
          {isLoadingWithdrawRequests ? (
            <div className="flex items-center justify-center px-4 py-8">
              <Spinner size="lg" />
              <p className="ml-4 text-default-500">
                Loading withdraw requests...
              </p>
            </div>
          ) : withdrawRequests.length === 0 ? (
            <div className="px-4 py-8 text-center text-default-500">
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
                  <TableColumn>ACTION</TableColumn>
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
                          {formatDecimal(String(item.shares), VAULT_DECIMALS, {
                            maximumFractionDigits: 9,
                          }) ?? "N/A"}
                        </span>
                      </TableCell>
                      <TableCell>
                        <span className="font-medium">
                          {formatCoinAmount(item.expected_amount, coinDecimals)}
                        </span>
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <Button
                            color="primary"
                            isDisabled={
                              isPending ||
                              cancellingWithdrawRequestId === item.request_id
                            }
                            size="sm"
                            onPress={() => handleExecuteWithdraw(item)}
                          >
                            Execute
                          </Button>
                          <Button
                            color="danger"
                            isDisabled={
                              isPending ||
                              cancellingWithdrawRequestId === item.request_id
                            }
                            isLoading={
                              cancellingWithdrawRequestId === item.request_id
                            }
                            size="sm"
                            variant="light"
                            onPress={() => handleCancelWithdraw(item)}
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
              <div className="mt-4 flex items-center justify-between border-t border-default-200 pt-4">
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

      {/* Execute Deposit Modal */}
      <ExecuteDepositModal
        assetTypes={assetTypes}
        coinDecimals={coinDecimals}
        isOpen={pendingDepositRequest !== null}
        operatorCaps={operatorCaps}
        request={pendingDepositRequest}
        vault={vault}
        onClose={() => setPendingDepositRequest(null)}
        onSuccess={refetchRequests}
      />

      {/* Execute Withdraw Modal */}
      <ExecuteWithdrawModal
        assetTypes={assetTypes}
        coinDecimals={coinDecimals}
        isOpen={pendingWithdrawRequest !== null}
        operatorCaps={operatorCaps}
        request={pendingWithdrawRequest}
        vault={vault}
        onClose={() => setPendingWithdrawRequest(null)}
        onSuccess={refetchRequests}
      />

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
