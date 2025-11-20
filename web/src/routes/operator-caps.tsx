import { Navigate } from "react-router-dom";
import { BreadcrumbItem, Breadcrumbs, Spinner } from "@heroui/react";

import { AppLayout } from "@/components/layout/AppLayout";
import { OperatorCapList } from "@/components/manage/OperatorCapList";
import { useAdminCap } from "@/hooks/useAdminCap";

/**
 * OperatorCap route component
 * Route: /manage/operator-caps
 * Only accessible to users with AdminCap
 */
export const OperatorCapRoute = () => {
  const { hasAdminCap, isLoading } = useAdminCap();

  if (isLoading) {
    return (
      <AppLayout>
        <Spinner variant="dots" />
      </AppLayout>
    );
  }

  // Redirect to manage page if user doesn't have AdminCap
  if (!hasAdminCap) {
    return <Navigate replace to="/manage" />;
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
