import type { VaultInfo } from "@/lib/types";

import {
  BreadcrumbItem,
  Breadcrumbs,
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
import { useNavigate } from "react-router-dom";
import { Refresh } from "iconoir-react";

import {
  useVaultRequestSizes,
  useInvalidateVaultRequestSizes,
} from "@/hooks/useVaultRequests";

interface VaultListProps {
  vaults: VaultInfo[];
  refetchRegistry: () => Promise<unknown>;
  isFetchingRegistry: boolean;
}

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

function formatCoinType(coinType: string): string {
  const parts = coinType.split("::");

  return parts[parts.length - 1] || coinType;
}

function formatTimestamp(timestampMs: number): string {
  const date = new Date(timestampMs);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffSeconds = Math.floor(diffMs / 1000);
  const diffMinutes = Math.floor(diffSeconds / 60);
  const diffHours = Math.floor(diffMinutes / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffSeconds < 60) {
    return `${diffSeconds} seconds ago`;
  }
  if (diffMinutes < 60) {
    return `${diffMinutes} minutes ago`;
  }
  if (diffHours < 24) {
    return `${diffHours} hours ago`;
  }
  if (diffDays < 30) {
    return `${diffDays} days ago`;
  }

  return date.toLocaleDateString();
}

/**
 * Component to display pending request count for a vault
 * Manages its own refetch and loading state
 */
function VaultPendingRequests({ vaultId }: { vaultId: string }) {
  const { data: sizes, isFetching } = useVaultRequestSizes(vaultId);

  // Show loading spinner when loading or fetching
  if (isFetching) {
    return <Spinner size="sm" variant="dots" />;
  }

  const depositCount = sizes?.depositRequestsSize ?? 0;
  const withdrawCount = sizes?.withdrawRequestsSize ?? 0;
  const totalCount = depositCount + withdrawCount;

  if (totalCount === 0) {
    return <span className="text-xs text-default-400">None</span>;
  }

  return (
    <div className="flex flex-col gap-1">
      {depositCount > 0 && (
        <div className="flex items-center gap-2">
          <span className="text-xs text-default-500">Deposit:</span>
          <span className="font-medium">{depositCount}</span>
        </div>
      )}
      {withdrawCount > 0 && (
        <div className="flex text-xs items-center gap-2">
          <span className="text-default-500">Withdraw:</span>
          {withdrawCount}
        </div>
      )}
    </div>
  );
}

/**
 * Manage vault list component
 * Displays all vaults with pending deposit request counts
 */
export function VaultList({
  vaults,
  refetchRegistry,
  isFetchingRegistry,
}: VaultListProps) {
  const navigate = useNavigate();
  const invalidateVaultRequestSizes = useInvalidateVaultRequestSizes();

  const refresh = async () => {
    // Refresh registry (list) first
    await refetchRegistry();
    // Then refresh all vault request counts
    invalidateVaultRequestSizes();
  };

  // Ensure vaults is always an array
  const vaultsList = vaults || [];

  if (vaultsList.length === 0) {
    return (
      <section className="space-y-6">
        <header className="space-y-2">
          <Breadcrumbs>
            <BreadcrumbItem>Vaults</BreadcrumbItem>
          </Breadcrumbs>
          <p className="text-default-500">
            Monitor queued deposits and withdrawals, and execute batched
            operations.
          </p>
        </header>

        <Card>
          <CardHeader>
            <h2 className="text-lg font-medium">Registered Vaults</h2>
          </CardHeader>
          <CardBody>
            <p className="text-default-500">No vaults registered yet.</p>
          </CardBody>
        </Card>
      </section>
    );
  }

  return (
    <section className="space-y-6">
      <header className="space-y-2">
        <Breadcrumbs>
          <BreadcrumbItem>Vaults</BreadcrumbItem>
        </Breadcrumbs>
        <p className="text-default-500">
          Monitor queued deposits and withdrawals, and execute batched
          operations.
        </p>
      </header>

      <Card>
        <CardHeader>
          Registered Vaults
          <span className="text-sm text-default-500 ml-auto">
            {vaultsList.length} {vaultsList.length === 1 ? "vault" : "vaults"}
          </span>
          <Button
            isIconOnly
            aria-label="Refresh vault list"
            isLoading={isFetchingRegistry}
            size="sm"
            variant="light"
            onPress={refresh}
          >
            <Refresh className="w-4 h-4" />
          </Button>
        </CardHeader>
        <CardBody>
          <Table aria-label="Vault list">
            <TableHeader>
              <TableColumn>VAULT ID</TableColumn>
              <TableColumn>COIN TYPE</TableColumn>
              <TableColumn>CREATOR</TableColumn>
              <TableColumn>CREATED</TableColumn>
              <TableColumn>PENDING REQUESTS</TableColumn>
            </TableHeader>
            <TableBody>
              {vaultsList.map((vault) => {
                const handleVaultClick = () => {
                  navigate(`/manage/${vault.vault_id}`);
                };

                return (
                  <TableRow
                    key={vault.vault_id}
                    className="cursor-pointer hover:bg-default-100"
                    onClick={handleVaultClick}
                  >
                    <TableCell>
                      <code className="text-xs">
                        {truncateAddress(vault.vault_id)}
                      </code>
                    </TableCell>
                    <TableCell>
                      <span className="font-medium">
                        {formatCoinType(vault.coin_type)}
                      </span>
                    </TableCell>
                    <TableCell>
                      <code className="text-xs">
                        {truncateAddress(vault.creator)}
                      </code>
                    </TableCell>
                    <TableCell>
                      {formatTimestamp(vault.created_at_ms)}
                    </TableCell>
                    <TableCell>
                      <VaultPendingRequests vaultId={vault.vault_id} />
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardBody>
      </Card>
    </section>
  );
}
