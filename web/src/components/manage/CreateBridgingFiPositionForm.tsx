import type { VaultInfo } from "@/lib/types";

import {
  Button,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
} from "@heroui/react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction } from "@mysten/sui/transactions";
import { useState } from "react";

import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";
const { errorLog } = loggers("app:manage:create-bridgingfi-position-form");

interface CreateBridgingFiPositionFormProps {
  vault: VaultInfo;
  isOpen: boolean;
  onClose: () => void;
  onSuccess?: () => void;
}

/**
 * Form component for creating and adding BridgingFiPosition to vault
 */
export function CreateBridgingFiPositionForm({
  vault,
  isOpen,
  onClose,
  onSuccess,
}: CreateBridgingFiPositionFormProps) {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();
  const { operatorCaps } = useOperatorCaps();

  const coinType = vault.coin_type;

  const [custodianAddress, setCustodianAddress] = useState("");
  const [apr, setApr] = useState(""); // APR as percentage (e.g., "5" for 5%)
  const [defiAssetId, setDefiAssetId] = useState("1"); // DeFi asset index
  const [error, setError] = useState<string | null>(null);

  // Reset form when modal closes
  const handleClose = () => {
    setCustodianAddress("");
    setApr("");
    setDefiAssetId("1");
    setError(null);
    onClose();
  };

  // Handle create position
  const handleCreate = async () => {
    if (!currentAccount) {
      setError("Wallet not connected");

      return;
    }

    // Validate custodian address
    if (!custodianAddress || !custodianAddress.startsWith("0x")) {
      setError("Please enter a valid custodian address");

      return;
    }

    // Validate APR
    const aprValue = parseFloat(apr);

    if (isNaN(aprValue) || aprValue <= 0 || aprValue > 100) {
      setError("Please enter a valid APR (0-100%)");

      return;
    }

    // Validate DeFi asset ID
    const defiAssetIdValue = parseInt(defiAssetId, 10);

    if (
      isNaN(defiAssetIdValue) ||
      defiAssetIdValue < 0 ||
      defiAssetIdValue > 255
    ) {
      setError("Please enter a valid DeFi asset index (0-255)");

      return;
    }

    // Validate operator cap
    if (!operatorCaps || operatorCaps.length === 0) {
      setError("No operator cap found for this vault");

      return;
    }

    const operatorCap = operatorCaps[0]; // Use first available cap

    if (!operatorCap) {
      setError("Invalid operator cap");

      return;
    }

    // Convert APR percentage to u256 format (1e9 precision)
    // e.g., 5% = 0.05 = 50000000 in 1e9 format
    const aprDecimal = BigInt(Math.floor(aprValue * 1e7)); // 5% = 50000000

    setError(null);

    try {
      const tx = new Transaction();

      // Step 1: Create BridgingFiPosition
      // Returns: BridgingFiPosition
      const position = tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::create_position`,
        typeArguments: [],
        arguments: [
          tx.pure.address(vault.vault_id),
          tx.pure.address(custodianAddress),
          tx.pure.u256(aprDecimal),
        ],
      });

      // Step 2: Add BridgingFiPosition to vault
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::add_new_defi_asset`,
        typeArguments: [
          coinType,
          `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
        ],
        arguments: [
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCap.objectId),
          tx.object(vault.vault_id),
          tx.pure.u8(defiAssetIdValue),
          position, // BridgingFiPosition from create_position
        ],
      });

      signAndExecute(
        {
          transaction: tx as any,
        },
        {
          onSuccess: () => {
            setCustodianAddress("");
            setApr("");
            setDefiAssetId("1");
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
              "Failed to create BridgingFiPosition",
            );
            setError(
              "Failed to create BridgingFiPosition. See console for details.",
            );
          },
        },
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : "Unknown error");
      errorLog("Create position error: %O", err);
    }
  };

  return (
    <Modal isOpen={isOpen} size="lg" onClose={handleClose}>
      <ModalContent>
        <ModalHeader>Create BridgingFi Position</ModalHeader>
        <ModalBody>
          <div className="space-y-4">
            <Input
              description="The custodian account address that will receive investment funds"
              errorMessage={
                error && !custodianAddress.startsWith("0x")
                  ? "Invalid address format"
                  : ""
              }
              isInvalid={!!error && !custodianAddress.startsWith("0x")}
              label="Custodian Account Address"
              placeholder="0x..."
              value={custodianAddress}
              onChange={(e) => setCustodianAddress(e.target.value)}
            />

            <Input
              description="Annual percentage rate (e.g., 5 for 5%)"
              endContent={<span className="text-default-400">%</span>}
              errorMessage={
                error &&
                (isNaN(parseFloat(apr)) ||
                  parseFloat(apr) <= 0 ||
                  parseFloat(apr) > 100)
                  ? "Please enter a valid APR (0-100%)"
                  : ""
              }
              isInvalid={
                !!error &&
                (isNaN(parseFloat(apr)) ||
                  parseFloat(apr) <= 0 ||
                  parseFloat(apr) > 100)
              }
              label="APR (Annual Percentage Rate)"
              max="100"
              min="0"
              placeholder="5.0"
              step="0.01"
              type="number"
              value={apr}
              onChange={(e) => setApr(e.target.value)}
            />

            <Input
              description="DeFi asset index (0-255). Must be unique to avoid conflicts."
              errorMessage={
                error &&
                (isNaN(parseInt(defiAssetId, 10)) ||
                  parseInt(defiAssetId, 10) < 0 ||
                  parseInt(defiAssetId, 10) > 255)
                  ? "Please enter a valid index (0-255)"
                  : ""
              }
              isInvalid={
                !!error &&
                (isNaN(parseInt(defiAssetId, 10)) ||
                  parseInt(defiAssetId, 10) < 0 ||
                  parseInt(defiAssetId, 10) > 255)
              }
              label="DeFi Asset Index"
              max="255"
              min="0"
              placeholder="1"
              type="number"
              value={defiAssetId}
              onChange={(e) => setDefiAssetId(e.target.value)}
            />

            {error && (
              <div className="rounded-lg bg-danger-50 dark:bg-danger-900/20 p-3">
                <p className="text-sm text-danger">{error}</p>
              </div>
            )}

            <div className="rounded-lg bg-default-100 p-4 space-y-2">
              <p className="text-sm font-semibold">Vault Information</p>
              <div className="text-sm">
                <p className="text-default-500">Vault ID</p>
                <code className="text-xs">{vault.vault_id}</code>
              </div>
              <div className="text-sm">
                <p className="text-default-500">Coin Type</p>
                <code className="text-xs">{coinType}</code>
              </div>
            </div>
          </div>
        </ModalBody>
        <ModalFooter>
          <Button variant="light" onPress={handleClose}>
            Cancel
          </Button>
          <Button
            color="primary"
            isDisabled={
              !currentAccount ||
              !custodianAddress ||
              !custodianAddress.startsWith("0x") ||
              !apr ||
              isNaN(parseFloat(apr)) ||
              parseFloat(apr) <= 0 ||
              parseFloat(apr) > 100 ||
              !defiAssetId ||
              isNaN(parseInt(defiAssetId, 10)) ||
              parseInt(defiAssetId, 10) < 0 ||
              parseInt(defiAssetId, 10) > 255 ||
              !operatorCaps ||
              operatorCaps.length === 0
            }
            isLoading={isPending}
            onPress={handleCreate}
          >
            Create Position
          </Button>
        </ModalFooter>
      </ModalContent>
    </Modal>
  );
}
