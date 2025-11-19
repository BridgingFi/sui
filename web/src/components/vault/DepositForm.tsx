import type { VaultInfo } from "@/lib/types";

import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Input,
  Spinner,
} from "@heroui/react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { useState } from "react";

import { useCoinBalance } from "@/hooks/useCoinBalance";
import { useUserReceipts } from "@/hooks/useUserReceipts";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { WalletConnectButtonWithModal } from "@/components/wallet/WalletConnectButtonWithModal";

const VOLO_VAULT_PACKAGE_ID = import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID || "";
const CLOCK_OBJECT_ID = "0x6"; // Standard Sui Clock object ID
const OPTION_PACKAGE_ID =
  "0x0000000000000000000000000000000000000000000000000000000000000001"; // Sui framework

// Helper function to get coin decimals (default to 6 for USDC, 9 for SUI)
function getCoinDecimals(coinType: string): number {
  // Most common: USDC has 6 decimals, SUI has 9 decimals
  // For now, we'll default to 6 for most coins
  // In production, you might want to query the coin metadata
  if (coinType.toLowerCase().includes("usdc")) {
    return 6;
  }
  if (coinType.toLowerCase().includes("sui")) {
    return 9;
  }

  return 6; // Default to 6 decimals
}

interface DepositFormProps {
  vault: VaultInfo;
}

/**
 * Deposit form component
 * Handles both new receipt and existing receipt deposits
 */
export function DepositForm({ vault }: DepositFormProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  // Use vault's coin_type instead of environment variable
  const coinType = vault.coin_type;
  const coinDecimals = getCoinDecimals(coinType);

  const { receipts, isLoading: isLoadingReceipts } = useUserReceipts(
    vault.vault_id,
  );
  const {
    balance,
    formattedBalance,
    isLoading: isLoadingBalance,
  } = useCoinBalance(coinType);

  useVaultInfo(vault.vault_id); // Query vault info for potential future use

  const [amount, setAmount] = useState("");
  const [error, setError] = useState<string | null>(null);

  // Check if user has a receipt for this vault
  const hasReceipt = receipts.length > 0;
  const receiptId = hasReceipt && receipts[0] ? receipts[0].id : null;

  // Handle MAX button click
  const handleMax = () => {
    if (balance > 0) {
      setAmount(balance.toFixed(6));
    }
  };

  // Handle Half button click
  const handleHalf = () => {
    if (balance > 0) {
      setAmount((balance / 2).toFixed(6));
    }
  };

  const handleDeposit = async () => {
    if (!currentAccount) {
      setError("Please connect your wallet");

      return;
    }

    if (!amount || isNaN(Number(amount)) || Number(amount) <= 0) {
      setError("Please enter a valid amount");

      return;
    }

    // Minimum investment: 1 USDC
    const minInvestment = 1.0;

    if (Number(amount) < minInvestment) {
      setError(
        `Minimum investment is ${minInvestment} ${coinType.split("::").pop() || "COIN"}`,
      );

      return;
    }

    setError(null);

    try {
      // Get user's coin balance
      const coins = await client.getCoins({
        owner: currentAccount.address,
        coinType,
      });

      if (coins.data.length === 0) {
        const coinName = coinType.split("::").pop() || "coins";

        setError(`You don't have any ${coinName} coins`);

        return;
      }

      // Use the first coin (in production, might need to merge coins)
      const coinId = coins.data[0]?.coinObjectId;

      if (!coinId) {
        setError("Invalid coin object");

        return;
      }
      const decimalsMultiplier = Math.pow(10, coinDecimals);
      const amountValue = BigInt(
        Math.floor(Number(amount) * decimalsMultiplier),
      );

      // can be improved to query the expected shares from the vault
      const expectedShares = 0n;

      const tx = new Transaction();

      // Get volo package ID from vault or environment
      const voloPackageId =
        VOLO_VAULT_PACKAGE_ID || vault.vault_id.split("::")[0];

      // Create Option<Receipt> by calling option::some or option::none
      // The return value of moveCall can be directly used as an argument
      let optionReceipt;

      if (hasReceipt && receiptId) {
        // Call option::some(receipt) to wrap receipt in Option
        optionReceipt = tx.moveCall({
          target: `${OPTION_PACKAGE_ID}::option::some`,
          typeArguments: [`${voloPackageId}::receipt::Receipt`],
          arguments: [tx.object(receiptId)],
        });
      } else {
        // Call option::none() to create Option::none
        optionReceipt = tx.moveCall({
          target: `${OPTION_PACKAGE_ID}::option::none`,
          typeArguments: [`${voloPackageId}::receipt::Receipt`],
          arguments: [],
        });
      }

      // Directly call volo's deposit_with_auto_transfer function
      // Use the return value from previous moveCall as argument
      tx.moveCall({
        target: `${voloPackageId}::user_entry::deposit_with_auto_transfer`,
        typeArguments: [coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(vault.reward_manager_id),
          tx.object(coinId),
          tx.pure.u64(amountValue),
          tx.pure.u256(expectedShares),
          optionReceipt, // Use the Option<Receipt> from previous call
          tx.object(CLOCK_OBJECT_ID),
        ],
      });

      signAndExecute(
        {
          transaction: tx as any,
        },
        {
          onSuccess: () => {
            setAmount("");
            setError(null);
            // TODO: Show success toast
          },
          onError: (err) => {
            setError(err.message || "Deposit failed");
          },
        },
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
    }
  };

  return (
    <Card>
      <CardHeader>
        <h2 className="text-lg font-medium">Stake</h2>
        {isLoadingReceipts && <Spinner className="ml-auto" size="sm" />}
      </CardHeader>
      <CardBody className="space-y-4">
        {/* Wallet Balance Display */}
        <div className="space-y-2">
          <p className="text-sm text-default-500">Amount</p>
          <div className="flex items-center gap-2">
            <Input
              classNames={{
                input: "text-lg",
                inputWrapper: "h-14",
              }}
              endContent={
                <div className="flex items-center gap-2">
                  <span className="text-default-500 text-sm">
                    {coinType.split("::").pop() || "COIN"}
                  </span>
                  {currentAccount && (
                    <div className="flex gap-1">
                      <Button
                        isDisabled={isLoadingBalance}
                        size="sm"
                        variant="light"
                        onPress={handleHalf}
                      >
                        Half
                      </Button>
                      <Button
                        isDisabled={isLoadingBalance}
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
              startContent={
                <div className="flex items-center justify-center w-6 h-6 rounded-full bg-default-200">
                  <span className="text-xs font-bold">$</span>
                </div>
              }
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
          </div>
          {currentAccount ? (
            <div className="flex items-center justify-between text-sm">
              <span className="text-default-500">
                {isLoadingBalance ? (
                  <Spinner size="sm" />
                ) : (
                  `$${formattedBalance}`
                )}
              </span>
              <div className="flex items-center gap-2">
                <span className="text-default-500">Balance:</span>
                <span className="font-medium">
                  {isLoadingBalance ? (
                    <Spinner size="sm" />
                  ) : (
                    `${formattedBalance} ${coinType.split("::").pop() || "COIN"}`
                  )}
                </span>
              </div>
            </div>
          ) : (
            <p className="text-sm text-default-500">
              Connect wallet to view balance
            </p>
          )}
        </div>

        {/* Investment Details */}
        <div className="space-y-2 pt-2 border-t border-default-200">
          <div className="flex items-center justify-between text-sm">
            <span className="text-default-500">Min Investment</span>
            <span className="font-medium">
              1 {coinType.split("::").pop() || "COIN"}
            </span>
          </div>
          <div className="flex items-center justify-between text-sm">
            <span className="text-default-500">Unstake Time</span>
            <span className="font-medium">14:00 UTC Daily</span>
          </div>
        </div>

        {/* Receipt Info */}
        {hasReceipt && currentAccount && (
          <div className="rounded-lg bg-default-100 p-3">
            <p className="text-xs text-default-500 mb-1">
              Using existing receipt
            </p>
            <p className="text-xs font-mono">
              {receiptId?.slice(0, 8)}...{receiptId?.slice(-6)}
            </p>
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
              !amount ||
              Number(amount) <= 0 ||
              Number(amount) < 1.0 ||
              Number(amount) > balance
            }
            isLoading={isPending}
            size="lg"
            onPress={handleDeposit}
          >
            Deposit
          </Button>
        )}
      </CardBody>
    </Card>
  );
}
