import { useAdminCap } from "@/hooks/useAdminCap";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";

/**
 * Hook to check if user has permission to access manage pages
 * User needs either AdminCap or OperatorCap
 */
export function useManagePermission() {
  const { hasAdminCap, isLoading: isLoadingAdminCap } = useAdminCap();
  const { operatorCaps, isLoading: isLoadingOperatorCaps } = useOperatorCaps();

  const hasPermission = hasAdminCap || operatorCaps.length > 0;
  const isLoading = isLoadingAdminCap || isLoadingOperatorCaps;

  return {
    hasPermission,
    isLoading,
    hasAdminCap,
    hasOperatorCap: operatorCaps.length > 0,
  };
}
