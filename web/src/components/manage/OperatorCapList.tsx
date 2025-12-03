import {
  addToast,
  Button,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Chip,
  Input,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
  ModalHeader,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
} from "@heroui/react";
import {
  useCurrentAccount,
  useSignAndExecuteTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { QueryEventsParams } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import { Refresh, Plus } from "iconoir-react";
import { useState } from "react";

import { useAllOperatorCaps } from "@/hooks/useAllOperatorCaps";
import { useAdminCap } from "@/hooks/useAdminCap";
import { loggers } from "@/utils/debug";
import { showTransactionErrorToast } from "@/utils/transaction";

const { errorLog } = loggers("app:manage:operator-cap-list");

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const PAGE_SIZE = 20;

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

/**
 * Manage OperatorCap list component
 * Displays OperatorCap objects created via events with pagination, with owner and freezed status
 */
export function OperatorCapList() {
  const client = useSuiClient();
  // Pagination state
  const [cursor, setCursor] = useState<QueryEventsParams["cursor"]>(null);
  const [cursors, setCursors] = useState<Array<QueryEventsParams["cursor"]>>(
    [],
  ); // History of cursors for "previous page"

  const { operatorCaps, isLoading, isFetching, pagination, refetch } =
    useAllOperatorCaps({
      limit: PAGE_SIZE,
      cursor,
    });
  const { adminCap, hasAdminCap } = useAdminCap();
  const currentAccount = useCurrentAccount();
  const { mutate: signAndExecute, isPending } = useSignAndExecuteTransaction();

  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [recipientAddress, setRecipientAddress] = useState("");
  const [isCreating, setIsCreating] = useState(false);

  // Set default address to current account when modal opens
  const handleOpenModal = () => {
    setRecipientAddress(currentAccount?.address || "");

    setIsCreateModalOpen(true);
  };

  const handleCloseModal = () => {
    setIsCreateModalOpen(false);

    setRecipientAddress("");
  };

  // Handle pagination
  const handleNextPage = () => {
    if (pagination.nextCursor) {
      setCursors([...cursors, cursor || null]);
      setCursor(pagination.nextCursor);
    }
  };

  const handlePreviousPage = () => {
    if (cursors.length > 0) {
      const newCursors = [...cursors];

      newCursors.pop();
      setCursors(newCursors);

      setCursor(
        newCursors.length > 0 ? newCursors[newCursors.length - 1] : undefined,
      );
    } else {
      setCursor(undefined);
    }
  };

  const handleCreateOperatorCap = async () => {
    if (!currentAccount || !adminCap || !recipientAddress) {
      addToast({
        title: "Missing required information",
        description:
          "Please ensure wallet is connected and recipient address is provided",
        color: "danger",
      });

      return;
    }

    // Validate address format (basic check)
    if (!recipientAddress.startsWith("0x") || recipientAddress.length < 10) {
      addToast({
        title: "Invalid address",
        description: "Please enter a valid Sui address",
        color: "danger",
      });

      return;
    }

    setIsCreating(true);

    try {
      const tx = new Transaction();

      // Call create_operator_cap which returns an OperatorCap
      const operatorCap = tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::vault_manage::create_operator_cap`,
        arguments: [tx.object(adminCap.objectId)],
      });

      // Transfer the OperatorCap to the recipient
      tx.transferObjects([operatorCap], recipientAddress);

      signAndExecute(
        {
          transaction: tx as any,
        },
        {
          onSuccess: async () => {
            setIsCreating(false);
            handleCloseModal();
            addToast({
              title: "Success",
              description: `OperatorCap created and transferred to ${truncateAddress(recipientAddress)}`,
              color: "success",
            });
            // Wait a bit for events to be indexed
            setTimeout(() => {
              refetch();
            }, 2000);
          },
          onError: (err) => {
            setIsCreating(false);
            showTransactionErrorToast(
              err,
              tx,
              client,
              errorLog,
              "Failed to create OperatorCap",
            );
          },
        },
      );
    } catch (err) {
      setIsCreating(false);
      errorLog("Create OperatorCap failed: %O", err);
      addToast({
        title: "Failed to create OperatorCap",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
    }
  };

  if (isLoading) {
    return <Spinner variant="dots" />;
  }

  return (
    <Card>
      <CardHeader>
        <h2 className="text-lg font-medium">OperatorCap Objects</h2>
        <div className="flex items-center gap-4 ml-auto">
          <span className="text-sm text-default-500">
            {operatorCaps.length} {operatorCaps.length === 1 ? "cap" : "caps"}
          </span>
          {hasAdminCap && (
            <Button
              color="primary"
              isDisabled={isPending || isCreating}
              size="sm"
              startContent={<Plus />}
              onPress={handleOpenModal}
            >
              Create
            </Button>
          )}
          <Button
            isIconOnly
            aria-label="Refresh OperatorCap list"
            isLoading={isFetching}
            size="sm"
            variant="light"
            onPress={() => refetch()}
          >
            <Refresh className="w-4 h-4" />
          </Button>
        </div>
      </CardHeader>
      <Divider />
      <CardBody className="p-0">
        {operatorCaps.length === 0 ? (
          <div className="text-center py-8 px-4 text-default-500">
            <p>No OperatorCap objects found.</p>
          </div>
        ) : (
          <>
            <Table
              aria-label="OperatorCap list"
              classNames={{
                wrapper: ["p-0", "rounded-none"],
                th: ["first:rounded-s-none", "last:rounded-e-none"],
              }}
            >
              <TableHeader>
                <TableColumn>OBJECT ID</TableColumn>
                <TableColumn>OWNER</TableColumn>
                <TableColumn>STATUS</TableColumn>
              </TableHeader>
              <TableBody>
                {operatorCaps.map((cap) => (
                  <TableRow key={cap.objectId}>
                    <TableCell>
                      <code className="text-xs">
                        {truncateAddress(cap.objectId)}
                      </code>
                    </TableCell>
                    <TableCell>
                      {cap.owner ? (
                        <code className="text-xs">
                          {truncateAddress(cap.owner)}
                        </code>
                      ) : (
                        <span className="text-xs text-default-400">
                          Unknown
                        </span>
                      )}
                    </TableCell>
                    <TableCell>
                      <Chip
                        color={cap.isFreezed ? "danger" : "success"}
                        size="sm"
                        variant="flat"
                      >
                        {cap.isFreezed ? "Freezed" : "Active"}
                      </Chip>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            {/* Pagination controls */}
            <div className="flex items-center justify-end gap-4 mt-2">
              <Button
                isDisabled={cursors.length === 0 && !cursor}
                size="sm"
                variant="light"
                onPress={handlePreviousPage}
              >
                Previous
              </Button>
              <span className="text-sm text-default-500">
                Page {cursors.length + 1}
              </span>
              <Button
                isDisabled={!pagination.hasNextPage}
                size="sm"
                variant="light"
                onPress={handleNextPage}
              >
                Next
              </Button>
            </div>
          </>
        )}
      </CardBody>

      {/* Create OperatorCap Modal */}
      <Modal isOpen={isCreateModalOpen} onClose={handleCloseModal}>
        <ModalContent>
          <ModalHeader>
            <h2 className="text-lg font-medium">Create OperatorCap</h2>
          </ModalHeader>
          <ModalBody>
            <Input
              label="Recipient Address"
              placeholder="0x..."
              value={recipientAddress}
              variant="bordered"
              onValueChange={setRecipientAddress}
            />
            <p className="text-xs text-default-500 mt-2">
              The OperatorCap will be created and transferred to this address.
            </p>
          </ModalBody>
          <ModalFooter>
            <Button color="danger" variant="light" onPress={handleCloseModal}>
              Cancel
            </Button>
            <Button
              color="primary"
              isLoading={isCreating || isPending}
              onPress={handleCreateOperatorCap}
            >
              Create & Transfer
            </Button>
          </ModalFooter>
        </ModalContent>
      </Modal>
    </Card>
  );
}
