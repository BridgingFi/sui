import { useParams, Navigate } from "react-router-dom";

import { AppLayout } from "@/components/layout/AppLayout";
import { AdminVaultDetail } from "@/components/admin/AdminVaultDetail";
import { AdminVaultList } from "@/components/admin/AdminVaultList";
import { useVaultRegistry } from "@/hooks/useVaultRegistry";

/**
 * Admin route component
 * Route: /admin or /admin/:vaultId
 */
export const AdminRoute = () => {
  const { vaultId } = useParams<{ vaultId?: string }>();
  const { vaults, isLoading, refetch, isFetching } = useVaultRegistry();

  if (isLoading) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center py-8">
          <p className="text-default-500">Loading vaults...</p>
        </div>
      </AppLayout>
    );
  }

  // If vaultId is provided, show vault detail
  if (vaultId) {
    const vault = vaults.find((v) => v.vault_id === vaultId);

    if (!vault) {
      return <Navigate replace to="/admin" />;
    }

    return (
      <AppLayout>
        <AdminVaultDetail vault={vault} />
      </AppLayout>
    );
  }

  // Otherwise show vault list
  // Note: isFetching is only passed when isLoading is false (component is rendered)
  // This is because isLoading = isFetching && !data, so if isLoading is true,
  // the component won't render anyway
  return (
    <AppLayout>
      <AdminVaultList
        isFetchingRegistry={isFetching}
        refetchRegistry={refetch}
        vaults={vaults || []}
      />
    </AppLayout>
  );
};
