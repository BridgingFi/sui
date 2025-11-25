import { Navigate } from "react-router-dom";
import { Spinner } from "@heroui/react";

import { AppLayout } from "@/components/layout/AppLayout";
import { OracleConfigDetail } from "@/components/manage/OracleConfigDetail";
import { useManagePermission } from "@/hooks/useManagePermission";

/**
 * Oracle Config route component
 * Route: /manage/oracle-config
 * Accessible to users with AdminCap or OperatorCap
 * AdminCap required for modifications
 */
export const OracleConfigRoute = () => {
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
      <div className="container mx-auto py-8">
        <h1 className="mb-6 text-2xl font-bold">Oracle Configuration</h1>
        <OracleConfigDetail />
      </div>
    </AppLayout>
  );
};
