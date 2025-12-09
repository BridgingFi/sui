import type { VaultInfo } from "@/lib/types";

import {
  Button,
  ButtonGroup,
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
} from "@heroui/react";
import { useCurrentAccount } from "@mysten/dapp-kit";
import { useMemo, useState } from "react";

import { DepositForm } from "@/components/vault/DepositForm";
import { WithdrawForm } from "@/components/vault/WithdrawForm";
import { VAULT_DECIMALS } from "@/lib/constants";
import { formatDecimal, fromDecimals, formatCoinAmount } from "@/utils/format";
import { useReceiptsDetails } from "@/hooks/useReceiptDetails";
import { useUserReceipts } from "@/hooks/useUserReceipts";
import { useVaultShareRatio } from "@/hooks/useVaultShareRatio";
import { useCoinDecimals } from "@/hooks/useCoinDecimals";
import { loggers } from "@/utils/debug";

const { errorLog } = loggers("app:vault:user-positions");

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
    // Calculate using BigInt to avoid precision loss from early division
    const decimalsSquared = VAULT_DECIMALS * VAULT_DECIMALS;
    const product = sharesBigInt * shareRatio;

    // Use generic decimal conversion function
    const value = fromDecimals(product, decimalsSquared);

    return value.toFixed(6);
  } catch (error) {
    errorLog(
      "Failed to calculate position value for shares %o and share ratio %o: %O",
      shares,
      shareRatio,
      error,
    );

    return "N/A";
  }
}

// Get pending status label and amount
function getPendingInfo(
  status: number,
  pendingDepositBalance: string,
  pendingWithdrawShares: string,
  coinDecimals: number | null,
): { label: string; amount: string } | null {
  switch (status) {
    case 1: // PENDING_DEPOSIT
      return {
        label: "Pending Deposit",
        amount: formatCoinAmount(pendingDepositBalance, coinDecimals),
      };
    case 2: // PENDING_WITHDRAW
      return {
        label: "Pending Withdraw",
        amount:
          (formatDecimal(pendingWithdrawShares, VAULT_DECIMALS, {
            maximumFractionDigits: 9,
          }) ?? "N/A") + " shares",
      };
    case 3: // PENDING_WITHDRAW_WITH_AUTO_TRANSFER
      return {
        label: "Pending Withdraw (Auto)",
        amount:
          (formatDecimal(pendingWithdrawShares, VAULT_DECIMALS, {
            maximumFractionDigits: 9,
          }) ?? "N/A") + " shares",
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
  const [withdrawModalReceiptId, setWithdrawModalReceiptId] = useState<
    string | null
  >(null);
  const currentAccount = useCurrentAccount();
  const {
    receipts,
    isLoading: isLoadingReceipts,
    refetch: refetchReceipts,
  } = useUserReceipts(vault.vault_id);

  // Get coin decimals from oracle config
  const coinDecimals = useCoinDecimals(vault.coin_type);

  // Get share ratio for calculating position values
  const { shareRatio, isLoading: isLoadingShareRatio } = useVaultShareRatio(
    vault.vault_id,
    vault.coin_type,
  );

  // Query receipt details for all receipts
  // Use useMemo to stabilize receiptIds array reference to avoid duplicate queries
  const receiptIds = useMemo(() => receipts.map((r) => r.id), [receipts]);
  const { detailsMap: receiptDetailsMap, refetch: refetchReceiptDetails } =
    useReceiptsDetails(vault.vault_id, receiptIds, vault.coin_type);

  if (!currentAccount) {
    return null;
  }

  return (
    <Card>
      <CardHeader>
        Your Positions
        {isLoadingReceipts && <Spinner className="ml-auto" size="sm" />}
      </CardHeader>
      <Divider />
      <CardBody className="p-0">
        {isLoadingReceipts ? (
          <div className="flex items-center justify-center px-4 py-4">
            <Spinner size="sm" />
          </div>
        ) : receipts.length === 0 ? (
          <div className="px-4 py-4 text-center text-default-500">
            <p className="text-sm">You have no positions in this vault.</p>
          </div>
        ) : (
          <Table
            aria-label="User positions"
            classNames={{
              wrapper: ["p-0", "rounded-none"],
              th: ["first:rounded-s-none", "last:rounded-e-none"],
            }}
          >
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
                      coinDecimals,
                    )
                  : null;
                const isPending = pendingInfo !== null;
                const canDeposit = !isPending && receiptDetails?.status === 0; // NORMAL status
                const canWithdraw =
                  !isPending &&
                  receiptDetails?.status === 0 &&
                  receiptDetails &&
                  BigInt(receiptDetails.shares) > 0n; // NORMAL status and has shares

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
                            (formatDecimal(
                              receiptDetails.shares,
                              VAULT_DECIMALS,
                              {
                                maximumFractionDigits: 9,
                              },
                            ) ?? "N/A")
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
                          <span className="text-xs text-default-400">N/A</span>
                        )}
                      </div>
                    </TableCell>
                    <TableCell>
                      {canDeposit || canWithdraw ? (
                        <ButtonGroup color="primary" size="sm" variant="ghost">
                          {canDeposit && (
                            <Button
                              onPress={() =>
                                setDepositModalReceiptId(receipt.id)
                              }
                            >
                              Deposit
                            </Button>
                          )}
                          {canWithdraw && (
                            <Button
                              onPress={() =>
                                setWithdrawModalReceiptId(receipt.id)
                              }
                            >
                              Withdraw
                            </Button>
                          )}
                        </ButtonGroup>
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
          refetchReceiptDetails();
        }}
      />

      {/* Withdraw Modal */}
      <WithdrawForm
        isOpen={withdrawModalReceiptId !== null}
        receiptDetails={
          withdrawModalReceiptId
            ? (receiptDetailsMap.get(withdrawModalReceiptId) ?? null)
            : null
        }
        vault={vault}
        onClose={() => setWithdrawModalReceiptId(null)}
        onSuccess={() => {
          // Refetch immediately and with delays since receipts may not be immediately available
          refetchReceipts();
          refetchReceiptDetails();
        }}
      />
    </Card>
  );
}
