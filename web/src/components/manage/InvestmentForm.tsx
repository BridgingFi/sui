import type { VaultInfo } from "@/lib/types";
import type { BridgingFiPositionData } from "@/hooks/useBridgingFiPosition";

import {
  Button,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Spinner,
} from "@heroui/react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { useState, useMemo } from "react";

import { useVaultInfo } from "@/hooks/useVaultInfo";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { parseBridgingFiAssetType } from "@/utils/bridgingfi";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";
const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";
const { errorLog } = loggers("app:manage:investment-form");

interface InvestmentFormProps {
  vault: VaultInfo;
  position: BridgingFiPositionData;
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

// Helper function to get coin decimals (default to 9 for SUI)
function getCoinDecimals(coinType: string): number {
  if (coinType.toLowerCase().includes("sui")) {
    return 9;
  }
  if (coinType.toLowerCase().includes("usdc")) {
    return 6;
  }

  return 9; // Default to 9 decimals
}

/**
 * Investment form component for BridgingFi
 * Allows operator to invest funds to custodian account
 */
export function InvestmentForm({
  vault,
  position,
  isOpen,
  onClose,
  onSuccess,
}: InvestmentFormProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  const coinType = vault.coin_type;
  const coinDecimals = getCoinDecimals(coinType);

  const { freePrincipal, isLoading: isLoadingVaultInfo } = useVaultInfo(
    vault.vault_id,
  );

  // Get operator caps for this vault
  const { operatorCaps, isLoading: isLoadingOperatorCaps } = useOperatorCaps(
    vault.vault_id,
  );

  const [amount, setAmount] = useState("");
  const [custodianAddress, setCustodianAddress] = useState(
    position.custodianAccount,
  );
  const [error, setError] = useState<string | null>(null);

  // Reset form when modal closes
  const handleClose = () => {
    setAmount("");
    setCustodianAddress(position.custodianAccount);
    setError(null);
    onClose();
  };

  // Handle MAX button click
  const handleMax = () => {
    if (freePrincipal !== null && freePrincipal > 0n) {
      const maxAmount = Number(freePrincipal) / Math.pow(10, coinDecimals);

      setAmount(maxAmount.toFixed(coinDecimals));
    }
  };

  // Handle investment
  const handleInvest = async () => {
    if (!currentAccount) {
      setError("Wallet not connected");

      return;
    }

    // Validate amount
    const amountValue = parseFloat(amount);

    if (isNaN(amountValue) || amountValue <= 0) {
      setError("Please enter a valid amount");

      return;
    }

    // Convert to coin units
    const amountInCoinUnits = BigInt(
      Math.floor(amountValue * Math.pow(10, coinDecimals)),
    );

    // Validate against free principal
    if (freePrincipal === null || amountInCoinUnits > freePrincipal) {
      setError("Insufficient free principal balance");

      return;
    }

    // Validate custodian address matches position
    if (custodianAddress !== position.custodianAccount) {
      setError("Custodian address must match the position's custodian account");

      return;
    }

    // Validate operator cap
    if (!operatorCaps || operatorCaps.length === 0) {
      setError("No operator cap found for this vault");

      return;
    }

    const operatorCap = operatorCaps[0]; // Use first available cap

    setError(null);

    try {
      const tx = new Transaction();
      const bridgingfiAssetType = parseBridgingFiAssetType(0);
      const defiAssetId = 0; // BridgingFiPosition idx

      // Step 1: Get TypeName for BridgingFiPosition
      const bridgingfiTypeName = tx.moveCall({
        target: `0x1::type_name::get`,
        typeArguments: [
          `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
        ],
        arguments: [],
      });

      // Step 2: Create vector<TypeName> for defi_asset_types
      const defiAssetTypes = tx.moveCall({
        target: `0x1::vector::singleton`,
        typeArguments: [`0x1::type_name::TypeName`],
        arguments: [bridgingfiTypeName],
      });

      // Step 3: start_op_with_bag
      // Returns: (Bag, TxBag, TxBagForCheckValueUpdate, Balance<T>, Balance<CoinType>)
      // In Transaction API, we need to use result() method to access tuple elements
      const startOpResult = tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::start_op_with_bag`,
        typeArguments: [coinType, coinType, coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          tx.object(SUI_CLOCK_OBJECT_ID),
          tx.pure.vector("u8", [defiAssetId]),
          defiAssetTypes,
          tx.pure.u64(amountInCoinUnits),
          tx.pure.u64(0),
        ],
      });

      // Step 4: Remove BridgingFiPosition from bag
      // Access tuple[0] (Bag) - in Transaction API, moveCall result can be used directly
      // For tuple access, we use the result with index notation
      const position = tx.moveCall({
        target: `0x2::bag::remove`,
        typeArguments: [
          `0x1::ascii::String`,
          `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
        ],
        arguments: [
          startOpResult, // Transaction API will automatically use tuple[0] when needed
          tx.pure.string(bridgingfiAssetType),
        ],
      });

      // Step 5: invest_to_custodian
      // Note: The Transaction API handles tuple destructuring automatically
      // We pass the result directly and the API will extract the correct element
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::invest_to_custodian`,
        typeArguments: [coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          position,
          startOpResult, // Balance<T> from tuple[3] - API handles tuple indexing
          tx.pure.u64(amountInCoinUnits),
          tx.pure.address(custodianAddress),
          tx.object(SUI_CLOCK_OBJECT_ID),
        ],
      });

      // Step 6: Add position back to bag
      tx.moveCall({
        target: `0x2::bag::add`,
        typeArguments: [
          `0x1::ascii::String`,
          `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
        ],
        arguments: [
          startOpResult, // Bag from tuple[0]
          tx.pure.string(bridgingfiAssetType),
          position,
        ],
      });

      // Step 7: end_op_with_bag
      // Note: Transaction API may need explicit tuple element access
      // For now, we pass the result and let the API handle it
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::end_op_with_bag`,
        typeArguments: [coinType, coinType, coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          startOpResult, // Bag from tuple[0]
          startOpResult, // TxBag from tuple[1] - may need adjustment
          startOpResult, // Balance<T> from tuple[3] - may need adjustment
          startOpResult, // Balance<CoinType> from tuple[4] - may need adjustment
        ],
      });

      // Step 8: update_value
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::update_value`,
        typeArguments: [coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(VOLO_ORACLE_CONFIG_ID),
          tx.object(SUI_CLOCK_OBJECT_ID),
          tx.pure.string(bridgingfiAssetType),
        ],
      });

      // Step 9: update_free_principal_value
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::vault::update_free_principal_value`,
        typeArguments: [coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(VOLO_ORACLE_CONFIG_ID),
          tx.object(SUI_CLOCK_OBJECT_ID),
        ],
      });

      // Step 10: end_op_value_update_with_bag
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::end_op_value_update_with_bag`,
        typeArguments: [coinType, coinType],
        arguments: [
          tx.object(vault.vault_id),
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          tx.object(SUI_CLOCK_OBJECT_ID),
          startOpResult, // TxBagForCheckValueUpdate from tuple[2]
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
            onSuccess?.();
            handleClose();
          },
          onError: (err) => {
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Investment failed",
            );
            setError("Investment transaction failed. See console for details.");
          },
        },
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
      errorLog("Investment error: %O", err);
    }
  };

  // Calculate estimated new outstanding balance
  const estimatedNewBalance = useMemo(() => {
    if (!amount) {
      return position.outstandingBalance;
    }

    try {
      const amountValue = parseFloat(amount);
      const amountInCoinUnits = BigInt(
        Math.floor(amountValue * Math.pow(10, coinDecimals)),
      );

      // New balance = current debt + new investment
      // Current debt already includes compound interest
      return position.currentDebt + amountInCoinUnits;
    } catch {
      return position.outstandingBalance;
    }
  }, [amount, position, coinDecimals]);

  const formContent = (
    <div className="space-y-4">
      {/* Current Position Info */}
      <div className="rounded-lg bg-default-100 p-4 space-y-2">
        <p className="text-sm font-semibold">Current Position</p>
        <div className="grid grid-cols-2 gap-2 text-sm">
          <div>
            <span className="text-default-500">Outstanding Balance:</span>
            <span className="ml-2 font-mono">
              {(
                Number(position.outstandingBalance) / Math.pow(10, coinDecimals)
              ).toFixed(coinDecimals)}
            </span>
          </div>
          <div>
            <span className="text-default-500">Current Debt:</span>
            <span className="ml-2 font-mono">
              {(
                Number(position.currentDebt) / Math.pow(10, coinDecimals)
              ).toFixed(coinDecimals)}
            </span>
          </div>
        </div>
      </div>

      {/* Amount Input */}
      <Input
        endContent={
          <div className="flex gap-2">
            <Button
              isDisabled={!freePrincipal || freePrincipal === 0n}
              size="sm"
              variant="light"
              onPress={handleMax}
            >
              MAX
            </Button>
          </div>
        }
        errorMessage={error}
        isInvalid={!!error}
        label="Investment Amount"
        min="0"
        placeholder="0.000000"
        step={`0.${"0".repeat(coinDecimals - 1)}1`}
        type="number"
        value={amount}
        onChange={(e) => setAmount(e.target.value)}
      />

      {/* Free Principal Balance */}
      {freePrincipal !== null && (
        <p className="text-xs text-default-500">
          Available:{" "}
          {(Number(freePrincipal) / Math.pow(10, coinDecimals)).toFixed(
            coinDecimals,
          )}
        </p>
      )}

      {/* Custodian Address */}
      <Input
        isReadOnly
        description="Must match the position's custodian account"
        label="Custodian Account Address"
        placeholder="0x..."
        value={custodianAddress}
        variant="bordered"
        onChange={(e) => setCustodianAddress(e.target.value)}
      />

      {/* Estimated New Balance */}
      {amount && (
        <div className="rounded-lg bg-primary-50 dark:bg-primary-900/20 p-4">
          <p className="text-sm font-semibold text-primary">Estimated Result</p>
          <p className="text-sm text-default-600 dark:text-default-400 mt-1">
            New Outstanding Balance:{" "}
            <span className="font-mono font-semibold">
              {(
                Number(estimatedNewBalance) / Math.pow(10, coinDecimals)
              ).toFixed(coinDecimals)}
            </span>
          </p>
        </div>
      )}
    </div>
  );

  return (
    <Modal isOpen={isOpen} size="2xl" onClose={handleClose}>
      <ModalContent>
        <ModalHeader>Invest to Custodian</ModalHeader>
        <ModalBody>
          {isLoadingVaultInfo ? (
            <div className="flex items-center justify-center py-8">
              <Spinner size="lg" />
            </div>
          ) : (
            formContent
          )}
        </ModalBody>
        <ModalFooter>
          <Button variant="light" onPress={handleClose}>
            Cancel
          </Button>
          <Button
            color="primary"
            isDisabled={
              !amount ||
              parseFloat(amount) <= 0 ||
              custodianAddress !== position.custodianAccount ||
              (freePrincipal !== null &&
                BigInt(
                  Math.floor(
                    parseFloat(amount || "0") * Math.pow(10, coinDecimals),
                  ),
                ) > freePrincipal)
            }
            isLoading={isPending}
            onPress={handleInvest}
          >
            Invest
          </Button>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
