import type { VaultInfo } from "@/lib/types";
import type { ReceiptDetails } from "@/hooks/useReceiptDetails";

import {
  addToast,
  Button,
  Card,
  CardBody,
  CardHeader,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalHeader,
} from "@heroui/react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { useState, useMemo } from "react";

import { useCoinDecimals } from "@/hooks/useCoinDecimals";
import { WalletConnectButtonWithModal } from "@/components/wallet/WalletConnectButtonWithModal";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";
import { VAULT_DECIMALS } from "@/lib/constants";
import { formatDecimal, toDecimals } from "@/utils/format";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const { errorLog } = loggers("app:vault:withdraw-form");

interface WithdrawFormProps {
  vault: VaultInfo;
  receiptDetails?: ReceiptDetails | null; // Optional receipt details (if already fetched)
  isOpen?: boolean; // Whether modal is open (for modal mode)
  onClose?: () => void; // Callback when modal closes
  onSuccess?: () => void; // Callback when withdraw succeeds
  title?: string; // Custom title for the form
}

/**
 * Withdraw form component
 * Handles withdraw requests for existing receipts
 * Can be used as a standalone card or inside a modal
 */
export function WithdrawForm({
  vault,
  receiptDetails: propReceiptDetails = null,
  isOpen,
  onClose,
  onSuccess,
  title,
}: WithdrawFormProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  // Use vault's coin_type instead of environment variable
  const coinType = vault.coin_type;
  const coinDecimals = useCoinDecimals(coinType);

  const [shares, setShares] = useState("");
  const [error, setError] = useState<string | null>(null);

  const receiptDetails = propReceiptDetails;
  const hasReceipt = receiptDetails !== null;
  const receiptId = receiptDetails?.receiptId ?? null;
  const receiptShares = receiptDetails?.shares ?? "0";
  const hasPendingWithdraw =
    receiptDetails?.status === 2 || receiptDetails?.status === 3; // PENDING_WITHDRAW or PENDING_WITHDRAW_WITH_AUTO_TRANSFER

  // Calculate available shares (total shares minus pending withdraw shares)
  const availableShares = useMemo(() => {
    if (!receiptDetails) return "0";
    const totalShares = BigInt(receiptDetails.shares);
    const pendingShares = BigInt(receiptDetails.pending_withdraw_shares || "0");
    const available = totalShares - pendingShares;

    return available > 0n ? available.toString() : "0";
  }, [receiptDetails]);

  // Format available shares for display
  const formattedAvailableShares = useMemo(() => {
    if (availableShares === "0") return "0";

    return (
      formatDecimal(availableShares, VAULT_DECIMALS, {
        maximumFractionDigits: 9,
      }) ?? "0"
    );
  }, [availableShares]);

  // Reset form when modal closes
  const handleClose = () => {
    setShares("");
    setError(null);
    onClose?.();
  };

  // Handle MAX button click
  const handleMax = () => {
    if (availableShares !== "0") {
      setShares(formattedAvailableShares);
    }
  };

  // Handle Half button click
  const handleHalf = () => {
    if (availableShares !== "0") {
      const halfShares = BigInt(availableShares) / 2n;
      const formatted = formatDecimal(halfShares.toString(), VAULT_DECIMALS, {
        maximumFractionDigits: 9,
      });

      if (formatted) {
        setShares(formatted);
      }
    }
  };

  const handleWithdraw = async () => {
    if (!currentAccount) {
      setError("Please connect your wallet");

      return;
    }

    if (!hasReceipt || !receiptId) {
      setError("Receipt not found");

      return;
    }

    if (!shares || isNaN(Number(shares)) || Number(shares) <= 0) {
      setError("Please enter a valid amount of shares");

      return;
    }

    // Convert shares to u256 (with VAULT_DECIMALS)
    const sharesValue = toDecimals(shares, VAULT_DECIMALS);
    const sharesBigInt = BigInt(sharesValue);

    if (sharesBigInt === 0n) {
      setError("Shares amount must be greater than 0");

      return;
    }

    // Check if shares exceed available shares
    const availableSharesBigInt = BigInt(availableShares);

    if (sharesBigInt > availableSharesBigInt) {
      setError("Insufficient shares available");

      return;
    }

    // For expected_amount, we can set it to 0 for now
    // The actual amount will be calculated when the withdraw is executed
    // This is a conservative approach - the user will get at least this amount
    const expectedAmount = 0n;

    setError(null);

    try {
      const tx = new Transaction();

      // Get volo package ID from vault or environment
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::user_entry::withdraw_with_auto_transfer`,
        typeArguments: [coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.pure.u256(sharesBigInt),
          tx.pure.u64(expectedAmount),
          tx.object(receiptId),
          tx.object(SUI_CLOCK_OBJECT_ID),
        ],
      });

      signAndExecute(
        {
          transaction: tx,
        },
        {
          onSuccess: () => {
            setShares("");
            setError(null);
            onSuccess?.();
            // Close modal if in modal mode
            if (isOpen !== undefined) {
              handleClose();
            }
            addToast({
              title: "Withdraw request sent successfully",
              description: "Now waiting for operator to execute.",
              color: "success",
            });
          },
          onError: (err) => {
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Withdraw request failed",
            );
          },
        },
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    }
  };

  const formContent = (
    <div className="space-y-4">
      {/* Shares Input */}
      <div className="space-y-2">
        <p className="text-sm text-default-500">Shares to Withdraw</p>
        <div className="flex items-center gap-2">
          <Input
            classNames={{
              input: "text-lg",
              inputWrapper: "h-14",
            }}
            endContent={
              <div className="flex items-center gap-2">
                <span className="text-sm text-default-500">Shares</span>
                {currentAccount && hasReceipt && (
                  <div className="flex gap-1">
                    <Button
                      isDisabled={availableShares === "0"}
                      size="sm"
                      variant="light"
                      onPress={handleHalf}
                    >
                      Half
                    </Button>
                    <Button
                      isDisabled={availableShares === "0"}
                      size="sm"
                      variant="light"
                      onPress={handleMax}
                    >
                      MAX
                    </Button>
                  </div>
                )}
              </div>
            }
            placeholder="0.00"
            type="number"
            value={shares}
            onChange={(e) => setShares(e.target.value)}
          />
        </div>
        {currentAccount && hasReceipt ? (
          <div className="flex items-center justify-between text-sm">
            <span className="text-default-500">Available Shares:</span>
            <span className="font-medium">
              {formattedAvailableShares} shares
            </span>
          </div>
        ) : (
          <p className="text-sm text-default-500">
            {!currentAccount
              ? "Connect wallet to view shares"
              : "Receipt not found"}
          </p>
        )}
      </div>

      {/* Receipt Info */}
      {hasReceipt && receiptId && (
        <div className="rounded-lg bg-default-100 p-3">
          <p className="mb-1 text-xs text-default-500">Receipt ID</p>
          <p className="font-mono text-sm">
            {receiptId.slice(0, 8)}...{receiptId.slice(-6)}
          </p>
          <div className="mt-2 space-y-1">
            <div className="flex items-center justify-between text-xs">
              <span className="text-default-500">Total Shares:</span>
              <span className="font-medium">
                {formatDecimal(receiptShares, VAULT_DECIMALS, {
                  maximumFractionDigits: 9,
                }) ?? "0"}{" "}
                shares
              </span>
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-default-500">Available:</span>
              <span className="font-medium">
                {formattedAvailableShares} shares
              </span>
            </div>
          </div>
          {hasPendingWithdraw && (
            <p className="mt-2 text-xs text-warning">
              ⚠️ This receipt has a pending withdraw. Please wait for it to be
              executed.
            </p>
          )}
        </div>
      )}

      {/* Error Message */}
      {error && (
        <div className="rounded-lg bg-danger-50 p-3">
          <p className="text-sm text-danger">{error}</p>
        </div>
      )}

      {/* Action Button */}
      {!currentAccount ? (
        <WalletConnectButtonWithModal
          connectButton={
            <Button fullWidth color="primary" size="lg">
              Connect Wallet
            </Button>
          }
        />
      ) : (
        <Button
          fullWidth
          color="primary"
          isDisabled={
            !shares ||
            Number(shares) <= 0 ||
            !hasReceipt ||
            !!hasPendingWithdraw ||
            BigInt(toDecimals(shares || "0", VAULT_DECIMALS)) >
              BigInt(availableShares)
          }
          isLoading={isPending}
          size="lg"
          onPress={handleWithdraw}
        >
          {hasPendingWithdraw ? "Pending Withdraw Exists" : "Request Withdraw"}
        </Button>
      )}
    </div>
  );

  // Determine title
  const formTitle = title || "Withdraw";

  // If used as modal
  if (isOpen !== undefined) {
    return (
      <Modal isOpen={isOpen} size="2xl" onClose={handleClose}>
        <ModalContent>
          <ModalHeader>
            <h2 className="text-lg font-medium">{formTitle}</h2>
          </ModalHeader>
          <ModalBody className="pb-6">{formContent}</ModalBody>
        </ModalContent>
      </Modal>
    );
  }

  // If used as standalone card
  return (
    <Card>
      <CardHeader>{formTitle}</CardHeader>
      <CardBody>{formContent}</CardBody>
    </Card>
  );
}
