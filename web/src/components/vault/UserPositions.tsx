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
import { useMemo, useState } from "react";

import { DepositForm } from "@/components/vault/DepositForm";
import { VAULT_DECIMALS } from "@/lib/constants";
import { useReceiptsDetails } from "@/hooks/useReceiptDetails";
import { useUserReceipts } from "@/hooks/useUserReceipts";
import { useVaultInfo } from "@/hooks/useVaultInfo";

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
// Shares need to be divided by DECIMALS for display since share_ratio is already a unit price
function formatShares(shares: string): string {
  try {
    const sharesBigInt = BigInt(shares);
    const sharesWithDecimals = sharesBigInt / VAULT_DECIMALS;
    const remainder = sharesBigInt % VAULT_DECIMALS;

    // Format with decimals if there's a remainder
    if (remainder === 0n) {
      return sharesWithDecimals.toLocaleString();
    }

    // Format with decimal places
    const decimalPart = remainder.toString().padStart(9, "0");
    const trimmedDecimal = decimalPart.replace(/0+$/, "");

    return trimmedDecimal.length > 0
      ? `${sharesWithDecimals.toLocaleString()}.${trimmedDecimal}`
      : sharesWithDecimals.toLocaleString();
  } catch {
    return shares;
  }
}

function calculatePositionValue(
  shares: string,
  shareRatio: bigint | null,
): string {
  if (!shareRatio || shareRatio === 0n) {
    return "N/A";
  }

  try {
    const sharesBigInt = BigInt(shares);

    // share_ratio from contract is (total_usd_value / total_shares) * DECIMALS
    // To get unit price, we need to divide by DECIMALS: unit_price = share_ratio / DECIMALS
    // value = (shares / DECIMALS) * (share_ratio / DECIMALS)
    //       = (shares * share_ratio) / (DECIMALS * DECIMALS)
    const sharesNormalized = sharesBigInt / VAULT_DECIMALS;
    const unitPrice = Number(shareRatio) / Number(VAULT_DECIMALS);
    const valueNum = Number(sharesNormalized) * unitPrice;

    return valueNum.toFixed(6);
  } catch {
    return "N/A";
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

interface ReceiptItem {
  id: string;
  vaultId: string;
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

  // Get share ratio for calculating position values
  const { shareRatio, isLoading: isLoadingShareRatio } = useVaultInfo(
    vault.vault_id,
  );

  // Query receipt details for all receipts
  // Use useMemo to stabilize receiptIds array reference to avoid duplicate queries
  const receiptIds = useMemo(() => receipts.map((r) => r.id), [receipts]);
  const { detailsMap: receiptDetailsMap } = useReceiptsDetails(
    vault.vault_id,
    receiptIds,
    vault.coin_type,
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
              <TableColumn key="receiptId">Receipt ID</TableColumn>
              <TableColumn key="sharesValue">Shares / Value</TableColumn>
              <TableColumn key="action">Action</TableColumn>
            </TableHeader>
            <TableBody items={receipts}>
              {(receipt: ReceiptItem) => {
                const receiptDetails = receiptDetailsMap?.get(receipt.id);

                // Get pending info from receipt details status
                // Note: useReceiptsDetails returns fields with underscore naming
                const pendingInfo = receiptDetails
                  ? getPendingInfo(
                      receiptDetails.status,
                      receiptDetails.pending_deposit_balance,
                      receiptDetails.pending_withdraw_shares,
                      vault.coin_type,
                    )
                  : null;
                const isPending = pendingInfo !== null;
                const canDeposit = !isPending && receiptDetails?.status === 0; // NORMAL status

                return (
                  <TableRow>
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
                      <div className="flex flex-col gap-1">
                        <div>
                          {receiptDetails ? (
                            formatShares(receiptDetails.shares)
                          ) : (
                            <Spinner size="sm" />
                          )}
                        </div>
                        {isLoadingShareRatio ? (
                          <Spinner size="sm" />
                        ) : receiptDetails ? (
                          <span className="font-mono text-xs text-default-500">
                            $
                            {calculatePositionValue(
                              receiptDetails.shares,
                              shareRatio,
                            )}
                          </span>
                        ) : (
                          <span className="text-default-400">N/A</span>
                        )}
                      </div>
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
              }}
            </TableBody>
          </Table>
        )}
      </CardBody>

      {/* Deposit Modal */}
      <DepositForm
        isOpen={depositModalReceiptId !== null}
        receiptDetails={
          depositModalReceiptId
            ? (receiptDetailsMap.get(depositModalReceiptId) ?? null)
            : null
        }
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
