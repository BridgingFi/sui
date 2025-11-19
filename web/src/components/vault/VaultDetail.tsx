import type { VaultInfo } from "@/lib/types";

import {
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
} from "@heroui/react";
import { useNavigate } from "react-router-dom";

import { DepositForm } from "@/components/vault/DepositForm";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { useVaultShareRatioHistory } from "@/hooks/useVaultShareRatioHistory";

interface VaultDetailProps {
  vault: VaultInfo;
}

/**
 * Vault detail page component
 * Displays vault information and deposit form
 */
export function VaultDetail({ vault }: VaultDetailProps) {
  const navigate = useNavigate();

  const {
    depositFeeRate,
    totalShares,
    isLoading: isLoadingVaultInfo,
  } = useVaultInfo(vault.vault_id);

  const { history: shareRatioHistory, isLoading: isLoadingHistory } =
    useVaultShareRatioHistory(vault.vault_id, 50);

  // Format share price for display (divide share_ratio by DECIMALS)
  // share_price = share_ratio / DECIMALS = total_usd_value / total_shares
  const formatSharePrice = (ratio: bigint | null): string => {
    if (ratio === null || ratio === 0n) {
      return "N/A";
    }

    const decimals = BigInt(1e9); // vault_utils::DECIMALS = 1_000_000_000
    const priceValue = Number(ratio) / Number(decimals);

    return priceValue.toFixed(6);
  };

  return (
    <section className="space-y-8">
      <header className="space-y-2">
        <button
          className="text-default-500 hover:text-foreground mb-4"
          onClick={() => navigate(-1)}
        >
          ← Back
        </button>
        <h1 className="text-3xl font-semibold">
          {vault.coin_type.split("::").pop() || "Vault"} Vault
        </h1>
        <p className="text-default-500">
          Vault ID: {vault.vault_id.slice(0, 8)}...{vault.vault_id.slice(-6)}
        </p>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="space-y-6">
          <Card>
            <CardHeader>
              <h2 className="text-lg font-medium">Vault Information</h2>
            </CardHeader>
            <CardBody className="space-y-4">
              <div>
                <p className="text-sm text-default-500">Coin Type</p>
                <p className="font-medium">{vault.coin_type}</p>
              </div>
              <div>
                <p className="text-sm text-default-500">Creator</p>
                <p className="font-mono text-sm">
                  {vault.creator.slice(0, 8)}...{vault.creator.slice(-6)}
                </p>
              </div>
              <div>
                <p className="text-sm text-default-500">Created</p>
                <p className="text-sm">
                  {new Date(vault.created_at_ms).toLocaleString()}
                </p>
              </div>

              {/* Vault Metrics */}
              <div className="pt-4 border-t border-default-200">
                <p className="text-sm font-medium mb-3">Vault Metrics</p>
                {isLoadingVaultInfo ? (
                  <div className="flex items-center gap-2">
                    <Spinner size="sm" />
                    <span className="text-sm text-default-500">Loading...</span>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-default-500">
                        Deposit Fee Rate
                      </span>
                      <span className="text-sm font-medium">
                        {depositFeeRate !== null
                          ? `${depositFeeRate / 100}%`
                          : "N/A"}
                      </span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="text-sm text-default-500">
                        Total Shares
                      </span>
                      <span className="text-sm font-medium font-mono">
                        {totalShares !== null ? totalShares.toString() : "N/A"}
                      </span>
                    </div>
                  </div>
                )}
              </div>
            </CardBody>
          </Card>
        </div>

        <div className="space-y-6">
          <DepositForm vault={vault} />
        </div>
      </div>

      {/* Share Price History */}
      <Card>
        <CardHeader>
          <h2 className="text-lg font-medium">Share Price History</h2>
        </CardHeader>
        <CardBody>
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
        </CardBody>
      </Card>

      <Spacer y={8} />
    </section>
  );
}
