import type { VaultInfo } from "@/lib/types";

import {
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
import { useCurrentAccount } from "@mysten/dapp-kit";
import { useState } from "react";

import { DepositForm } from "@/components/vault/DepositForm";
import { useReceiptDetailsBatch } from "@/hooks/useReceiptDetails";
import { useUserReceipts } from "@/hooks/useUserReceipts";

// Helper function to get coin decimals
function getCoinDecimals(coinType: string): number {
  if (coinType.toLowerCase().includes("usdc")) {
    return 6;
  }
  if (coinType.toLowerCase().includes("sui")) {
    return 9;
  }

  return 6;
}

// Format amount with decimals
function formatAmount(amount: bigint | string, coinType: string): string {
  const decimals = getCoinDecimals(coinType);
  const amountNum = typeof amount === "string" ? BigInt(amount) : amount;
  const divisor = BigInt(10 ** decimals);
  const wholePart = amountNum / divisor;
  const fractionalPart = amountNum % divisor;
  const fractionalStr = fractionalPart.toString().padStart(decimals, "0");
  const trimmedFractional = fractionalStr.replace(/0+$/, "");

  return trimmedFractional.length > 0
    ? `${wholePart}.${trimmedFractional}`
    : wholePart.toString();
}

// Format shares (u256 as string)
function formatShares(shares: string): string {
  try {
    const sharesBigInt = BigInt(shares);

    // Shares are typically large numbers, format with commas
    return sharesBigInt.toLocaleString();
  } catch {
    return shares;
  }
}

// Get pending status label and amount
function getPendingInfo(
  status: number,
  pendingDepositBalance: string,
  pendingWithdrawShares: string,
  coinType: string,
): { label: string; amount: string } | null {
  switch (status) {
    case 1: // PENDING_DEPOSIT
      return {
        label: "Pending Deposit",
        amount: formatAmount(pendingDepositBalance, coinType),
      };
    case 2: // PENDING_WITHDRAW
      return {
        label: "Pending Withdraw",
        amount: formatShares(pendingWithdrawShares) + " shares",
      };
    case 3: // PENDING_WITHDRAW_WITH_AUTO_TRANSFER
      return {
        label: "Pending Withdraw (Auto)",
        amount: formatShares(pendingWithdrawShares) + " shares",
      };
    default:
      return null;
  }
}

interface UserPositionsProps {
  vault: VaultInfo;
}

/**
 * Component to display user's positions (receipts) for a vault
 */
export function UserPositions({ vault }: UserPositionsProps) {
  const [depositModalReceiptId, setDepositModalReceiptId] = useState<
    string | null
  >(null);
  const currentAccount = useCurrentAccount();
  const {
    receipts,
    isLoading: isLoadingReceipts,
    refetch: refetchReceipts,
  } = useUserReceipts(vault.vault_id);

  // Query receipt details for all receipts
  const receiptIds = receipts.map((r) => r.id);
  const { detailsMap, isLoading: isLoadingDetails } = useReceiptDetailsBatch(
    vault.vault_id,
    receiptIds,
  );

  if (!currentAccount) {
    return null;
  }

  return (
    <Card>
      <CardHeader>
        Your Positions
        {isLoadingReceipts && <Spinner className="ml-auto" size="sm" />}
      </CardHeader>
      <CardBody>
        {isLoadingReceipts ? (
          <div className="flex items-center justify-center py-4">
            <Spinner size="sm" />
          </div>
        ) : receipts.length === 0 ? (
          <div className="py-4 text-center text-default-500">
            <p className="text-sm">You have no positions in this vault.</p>
          </div>
        ) : (
          <Table aria-label="User positions">
            <TableHeader>
              <TableColumn>Receipt ID</TableColumn>
              <TableColumn>Shares</TableColumn>
              <TableColumn>Action</TableColumn>
            </TableHeader>
            <TableBody>
              {receipts.map((receipt) => {
                const receiptDetails = detailsMap[receipt.id];
                const isLoadingReceiptDetails =
                  isLoadingDetails || receiptDetails === undefined;

                // Get pending info from receipt details status
                const pendingInfo = receiptDetails
                  ? getPendingInfo(
                      receiptDetails.status,
                      receiptDetails.pendingDepositBalance,
                      receiptDetails.pendingWithdrawShares,
                      vault.coin_type,
                    )
                  : null;
                const isPending = pendingInfo !== null;
                const canDeposit = !isPending && receiptDetails?.status === 0; // NORMAL status

                return (
                  <TableRow key={receipt.id}>
                    <TableCell className="font-mono text-sm">
                      <div className="flex flex-col gap-1">
                        <span>
                          {receipt.id.slice(0, 8)}...{receipt.id.slice(-6)}
                        </span>
                        {pendingInfo && (
                          <span className="text-xs text-warning">
                            {pendingInfo.label}: {pendingInfo.amount}{" "}
                            {pendingInfo.label.includes("Deposit") &&
                              vault.coin_type.split("::").pop()}
                          </span>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      {isLoadingReceiptDetails ? (
                        <Spinner size="sm" />
                      ) : receiptDetails ? (
                        formatShares(receiptDetails.shares)
                      ) : (
                        <span className="text-default-400">N/A</span>
                      )}
                    </TableCell>
                    <TableCell>
                      {canDeposit ? (
                        <Button
                          color="primary"
                          size="sm"
                          variant="flat"
                          onPress={() => setDepositModalReceiptId(receipt.id)}
                        >
                          Deposit
                        </Button>
                      ) : (
                        <span className="text-xs text-default-400">
                          {isPending ? "Pending" : "N/A"}
                        </span>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </CardBody>

      {/* Deposit Modal */}
      <DepositForm
        isOpen={depositModalReceiptId !== null}
        receiptId={depositModalReceiptId}
        vault={vault}
        onClose={() => setDepositModalReceiptId(null)}
        onSuccess={() => {
          // Refetch immediately and with delays since receipts may not be immediately available
          refetchReceipts();
          setTimeout(() => {
            refetchReceipts();
          }, 2000);
          setTimeout(() => {
            refetchReceipts();
          }, 5000);
        }}
      />
    </Card>
  );
}
