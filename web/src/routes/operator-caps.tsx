import { Navigate } from "react-router-dom";
import { BreadcrumbItem, Breadcrumbs, Spinner } from "@heroui/react";

import { AppLayout } from "@/components/layout/AppLayout";
import { OperatorCapList } from "@/components/manage/OperatorCapList";
import { useManagePermission } from "@/hooks/useManagePermission";

/**
 * OperatorCap route component
 * Route: /manage/operator-caps
 * Only accessible to users with AdminCap
 */
export const OperatorCapRoute = () => {
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

  return (
    <AppLayout>
      <section className="space-y-6">
        <header className="space-y-2">
          <Breadcrumbs>
            <BreadcrumbItem href="/manage">Manage</BreadcrumbItem>
            <BreadcrumbItem>OperatorCap</BreadcrumbItem>
          </Breadcrumbs>
          <p className="text-default-500">
            Manage your OperatorCap objects. OperatorCap is required to execute
            operations on vaults.
          </p>
        </header>
        <OperatorCapList />
      </section>
    </AppLayout>
  );
};
