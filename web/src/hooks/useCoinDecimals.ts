import { useMemo } from "react";

import { useOracleConfig } from "@/hooks/useOracleConfig";

/**
 * Hook to get coin decimals from oracle config
 * Returns the decimals value from PriceInfo in oracle config for the given coinType
 * Returns null if oracle config is not loaded or coin type not found
 *
 * @param coinType - The coin type string (e.g., "0x123::usdc::USDC" or "123::usdc::USDC")
 * @returns The decimals value (number) or null if not found/loading
 */
export function useCoinDecimals(coinType: string): number | null {
  const { oracleConfig, isLoading } = useOracleConfig();

  const coinDecimals = useMemo(() => {
    // If oracle config is still loading, return null
    if (isLoading || !oracleConfig) {
      return null;
    }

    // Try to get decimals from oracle config using coin type
    // Remove 0x prefix if present for lookup (oracle config stores keys without 0x)
    const lookupKey = coinType.startsWith("0x") ? coinType.slice(2) : coinType;
    const priceInfo = oracleConfig.aggregators.get(lookupKey);

    if (!priceInfo || !priceInfo.decimals) {
      return null;
    }

    return priceInfo.decimals;
  }, [oracleConfig, isLoading, coinType]);

  return coinDecimals;
}

