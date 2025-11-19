import type { VaultInfo } from "@/lib/types";

import { useNavigate } from "react-router-dom";
import {
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

import { useVaultRegistry } from "@/hooks/useVaultRegistry";

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

function formatCoinType(coinType: string): string {
  // Extract coin name from type string (e.g., "0x...::usdc::USDC" -> "USDC")
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
 * Component to display list of registered vaults
 */
export function VaultList() {
  const navigate = useNavigate();
  const { vaults, isLoading, error } = useVaultRegistry();

  const handleVaultClick = (vault: VaultInfo) => {
    navigate(`/vault/${vault.vault_id}`);
  };

  if (isLoading) {
    return (
      <Card>
        <CardBody className="flex items-center justify-center py-8">
          <Spinner size="lg" />
          <p className="mt-4 text-default-500">Loading vaults...</p>
        </CardBody>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardBody>
          <p className="text-danger">Error loading vaults: {error.message}</p>
        </CardBody>
      </Card>
    );
  }

  if (vaults.length === 0) {
    return (
      <Card>
        <CardHeader>
          <h2 className="text-lg font-medium">Registered Vaults</h2>
        </CardHeader>
        <CardBody>
          <p className="text-default-500">No vaults registered yet.</p>
        </CardBody>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <h2 className="text-lg font-medium">Registered Vaults</h2>
        <span className="text-sm text-default-500 ml-auto">
          {vaults.length} {vaults.length === 1 ? "vault" : "vaults"}
        </span>
      </CardHeader>
      <CardBody>
        <Table aria-label="Vault list">
          <TableHeader>
            <TableColumn>VAULT ID</TableColumn>
            <TableColumn>COIN TYPE</TableColumn>
            <TableColumn>CREATOR</TableColumn>
            <TableColumn>CREATED</TableColumn>
          </TableHeader>
          <TableBody>
            {vaults.map((vault) => (
              <TableRow
                key={vault.vault_id}
                className="cursor-pointer hover:bg-default-100"
                onClick={() => handleVaultClick(vault)}
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
                <TableCell>{formatTimestamp(vault.created_at_ms)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardBody>
    </Card>
  );
}
