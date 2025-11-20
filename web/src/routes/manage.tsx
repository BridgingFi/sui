import { useParams, Navigate } from "react-router-dom";
import { Spinner } from "@heroui/react";

import { AppLayout } from "@/components/layout/AppLayout";
import { VaultDetail } from "@/components/manage/VaultDetail";
import { VaultList } from "@/components/manage/VaultList";
import { useVaultRegistry } from "@/hooks/useVaultRegistry";
import { useManagePermission } from "@/hooks/useManagePermission";

/**
 * Manage route component
 * Route: /manage or /manage/:vaultId
 * Accessible to users with AdminCap or OperatorCap
 */
export const ManageRoute = () => {
  const { vaultId } = useParams<{ vaultId?: string }>();
  const { vaults, isLoading, refetch, isFetching } = useVaultRegistry();
  const { hasPermission, isLoading: isLoadingPermission } =
    useManagePermission();

  // Check permissions first
  if (isLoadingPermission) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center py-8">
          <Spinner size="lg" />
        </div>
      </AppLayout>
    );
  }

  // Redirect to home if user doesn't have permission
  if (!hasPermission) {
    return <Navigate replace to="/" />;
  }

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
      return <Navigate replace to="/manage" />;
    }

    return (
      <AppLayout>
        <VaultDetail vault={vault} />
      </AppLayout>
    );
  }

  // Otherwise show vault list
  // Note: isFetching is only passed when isLoading is false (component is rendered)
  // This is because isLoading = isFetching && !data, so if isLoading is true,
  // the component won't render anyway
  return (
    <AppLayout>
      <VaultList
        isFetchingRegistry={isFetching}
        refetchRegistry={refetch}
        vaults={vaults || []}
      />
    </AppLayout>
  );
};
