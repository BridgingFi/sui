import type { VaultInfo } from "@/lib/types";

import {
  BreadcrumbItem,
  Breadcrumbs,
  Button,
  Card,
  CardBody,
  CardHeader,
  Spacer,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
  Tooltip,
} from "@heroui/react";
import { WarningTriangle } from "iconoir-react";

import { CopyButton } from "@/components/common/CopyButton";
import { DepositForm } from "@/components/vault/DepositForm";
import { UserPositions } from "@/components/vault/UserPositions";
import { VAULT_DECIMALS } from "@/lib/constants";
import { useUserReceipts } from "@/hooks/useUserReceipts";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { useVaultShareRatioHistoryGraphQL } from "@/hooks/useVaultShareRatioHistoryGraphQL";

interface VaultDetailProps {
  vault: VaultInfo;
}

function truncateCoinType(coinType: string): string {
  if (coinType.length <= 30) {
    return coinType;
  }

  return `${coinType.slice(0, 20)}...${coinType.slice(-10)}`;
}

/**
 * Vault detail page component
 * Displays vault information and deposit form
 */
export function VaultDetail({ vault }: VaultDetailProps) {
  const {
    depositFeeRate,
    totalShares,
    withdrawFeeRate,
    lockingTimeForWithdraw,
    lockingTimeForCancelRequest,
    shareRatio,
    isLoading: isLoadingVaultInfo,
  } = useVaultInfo(vault.vault_id);

  const {
    history: shareRatioHistory,
    isLoading: isLoadingHistory,
    loadMore,
    hasMore,
    oldestTimestamp,
  } = useVaultShareRatioHistoryGraphQL(vault.vault_id, 50);

  // Check if user has receipts for this vault
  const { receipts, refetch: refetchReceipts } = useUserReceipts(
    vault.vault_id,
  );
  const hasReceipts = receipts.length > 0;

  // Handle deposit success to refresh positions
  // Use delayed refetch with retries since receipts may not be immediately available
  const handleDepositSuccess = () => {
    // First refetch immediately
    refetchReceipts();

    // Then retry after delays since receipts may not be immediately available
    setTimeout(() => {
      refetchReceipts();
    }, 2000); // Retry after 2 seconds

    setTimeout(() => {
      refetchReceipts();
    }, 5000); // Retry after 5 seconds
  };

  // Format share price for display (divide share_ratio by DECIMALS)
  // share_price = share_ratio / DECIMALS = total_usd_value / total_shares
  const formatSharePrice = (ratio: bigint | null): string => {
    if (ratio === null) {
      return "N/A";
    }

    if (ratio === 0n) {
      return "0.000000";
    }

    const priceValue = Number(ratio) / Number(VAULT_DECIMALS);

    return priceValue.toFixed(6);
  };

  // Get latest share price from useVaultInfo (get_share_ratio_without_update)
  // If shareRatio is null, it means the call failed - show error state
  const latestSharePrice = formatSharePrice(shareRatio);

  // Format locking time from milliseconds to human readable format
  const formatLockingTime = (ms: number | null): string => {
    if (ms === null || ms === 0) {
      return "N/A";
    }

    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);

    if (days > 0) {
      return `${days} day${days > 1 ? "s" : ""}`;
    }
    if (hours > 0) {
      return `${hours} hour${hours > 1 ? "s" : ""}`;
    }
    if (minutes > 0) {
      return `${minutes} minute${minutes > 1 ? "s" : ""}`;
    }

    return `${seconds} second${seconds > 1 ? "s" : ""}`;
  };

  return (
    <section className="space-y-8">
      <header className="space-y-2">
        <Breadcrumbs>
          <BreadcrumbItem href="/">Home</BreadcrumbItem>
          <BreadcrumbItem>
            <div className="flex items-center">
              <Tooltip content={vault.vault_id}>
                <span>
                  Vault: {vault.vault_id.slice(0, 8)}...
                  {vault.vault_id.slice(-6)}
                </span>
              </Tooltip>
              <CopyButton disableTooltip value={vault.vault_id} />
            </div>
          </BreadcrumbItem>
        </Breadcrumbs>
        <h1 className="text-3xl font-semibold">
          {vault.coin_type.split("::").pop() || "Vault"} Vault
        </h1>
        <div className="flex items-center gap-4 text-sm text-default-500">
          <div className="flex items-center">
            <Tooltip content={vault.coin_type}>
              <span className="flex text-sm text-default-500">
                Coin Type: {truncateCoinType(vault.coin_type)}
              </span>
            </Tooltip>
            <CopyButton disableTooltip value={vault.coin_type} />
          </div>
          <span>
            Creator: {vault.creator.slice(0, 8)}...{vault.creator.slice(-6)}
          </span>
          <span>Created: {new Date(vault.created_at_ms).toLocaleString()}</span>
        </div>
      </header>

      {/* Vault Information - Full width */}
      <Card>
        <CardHeader>Vault Information</CardHeader>
        <CardBody>
          {/* Vault Metrics */}
          {isLoadingVaultInfo ? (
            <div className="flex items-center gap-2">
              <Spinner size="sm" />
              <span className="text-sm text-default-500">Loading...</span>
            </div>
          ) : (
            <div className="space-y-1">
              <div className="flex items-center justify-between">
                <span className="text-sm text-default-500">
                  Deposit Fee Rate
                </span>
                <span className="text-sm font-medium">
                  {depositFeeRate !== null ? `${depositFeeRate / 100}%` : "N/A"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-default-500">
                  Withdraw Fee Rate
                </span>
                <span className="text-sm font-medium">
                  {withdrawFeeRate !== null
                    ? `${withdrawFeeRate / 100}%`
                    : "N/A"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-default-500">Total Shares</span>
                <span className="text-sm font-medium font-mono">
                  {totalShares !== null ? totalShares.toString() : "N/A"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-default-500">
                  Locking Time for Withdraw
                </span>
                <span className="text-sm font-medium">
                  {formatLockingTime(lockingTimeForWithdraw)}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-sm text-default-500">
                  Locking Time for Cancel Request
                </span>
                <span className="text-sm font-medium">
                  {formatLockingTime(lockingTimeForCancelRequest)}
                </span>
              </div>
            </div>
          )}
        </CardBody>
      </Card>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* User Positions - Right column on desktop, Order 1 on mobile */}
        <div className="space-y-6 lg:order-2">
          <UserPositions vault={vault} />
          <DepositForm
            title={hasReceipts ? "New Position" : "Deposit"}
            vault={vault}
            onSuccess={handleDepositSuccess}
          />
        </div>

        {/* Share Price - Left column on desktop, Order 2 on mobile */}
        <div className="lg:order-1">
          <Card>
            <CardHeader>Share Price</CardHeader>
            <CardBody>
              <span className="text-2xl">
                {isLoadingVaultInfo ? (
                  <Spinner size="sm" variant="wave" />
                ) : shareRatio === null ? (
                  <WarningTriangle />
                ) : (
                  latestSharePrice
                )}
              </span>
              {isLoadingHistory ? (
                <div className="flex items-center justify-center py-8">
                  <Spinner size="lg" />
                </div>
              ) : shareRatioHistory.length === 0 ? (
                <div className="text-center py-8 text-default-500">
                  <p>No share price history available.</p>
                  <p className="text-sm mt-2">
                    Share price events are emitted when deposits or withdrawals
                    occur.
                  </p>
                </div>
              ) : (
                <Table aria-label="Share price history">
                  <TableHeader>
                    <TableColumn>Timestamp</TableColumn>
                    <TableColumn>Share Price</TableColumn>
                    <TableColumn>Transaction</TableColumn>
                  </TableHeader>
                  <TableBody>
                    {shareRatioHistory.map((item, index) => (
                      <TableRow key={`${item.transactionDigest}-${index}`}>
                        <TableCell>
                          {item.timestamp > 0
                            ? new Date(item.timestamp).toLocaleString()
                            : "N/A"}
                        </TableCell>
                        <TableCell className="font-mono">
                          {formatSharePrice(item.shareRatio)}
                        </TableCell>
                        <TableCell>
                          <a
                            className="text-primary hover:underline text-sm"
                            href={`https://suiscan.xyz/mainnet/tx/${item.transactionDigest}`}
                            rel="noopener noreferrer"
                            target="_blank"
                          >
                            {item.transactionDigest.slice(0, 8)}...
                            {item.transactionDigest.slice(-6)}
                          </a>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
              {shareRatioHistory.length > 0 && (
                <div className="mt-4 space-y-2">
                  {oldestTimestamp && (
                    <p className="text-sm text-default-500 text-center">
                      Loaded up to: {new Date(oldestTimestamp).toLocaleString()}
                    </p>
                  )}
                  {hasMore && (
                    <div className="flex justify-center">
                      <Button
                        color="primary"
                        isLoading={isLoadingHistory}
                        variant="flat"
                        onPress={loadMore}
                      >
                        Load More
                      </Button>
                    </div>
                  )}
                </div>
              )}
            </CardBody>
          </Card>
        </div>
      </div>

      <Spacer y={8} />
    </section>
  );
}
