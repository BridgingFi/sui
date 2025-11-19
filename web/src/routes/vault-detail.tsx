import { useParams, Navigate } from "react-router-dom";

import { AppLayout } from "@/components/layout/AppLayout";
import { VaultDetail } from "@/components/vault/VaultDetail";
import { useVaultRegistry } from "@/hooks/useVaultRegistry";

/**
 * Vault detail page route
 * Route: /vault/:vaultId
 */
export const VaultDetailRoute = () => {
  const { vaultId } = useParams<{ vaultId: string }>();
  const { vaults, isLoading } = useVaultRegistry();

  if (isLoading) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center py-8">
          <p className="text-default-500">Loading vault...</p>
        </div>
      </AppLayout>
    );
  }

  const vault = vaults.find((v) => v.vault_id === vaultId);

  if (!vault) {
    return <Navigate to="/" replace />;
  }

  return (
    <AppLayout>
      <VaultDetail vault={vault} />
    </AppLayout>
  );
};

