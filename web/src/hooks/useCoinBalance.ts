import { useSuiClientQuery, useCurrentAccount } from "@mysten/dapp-kit";

const USDC_COIN_TYPE =
  import.meta.env.VITE_USDC_COIN_TYPE ||
  "0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC";

/**
 * Hook to query user's coin balance for a specific coin type
 * @param coinType - The coin type to query (defaults to USDC)
 * @returns Balance in smallest unit (e.g., for USDC with 6 decimals, returns value * 10^6)
 */
export function useCoinBalance(coinType: string = USDC_COIN_TYPE) {
  const currentAccount = useCurrentAccount();

  const {
    data: balanceData,
    isLoading,
    error,
    refetch,
  } = useSuiClientQuery(
    "getBalance",
    {
      owner: currentAccount?.address || "",
      coinType,
    },
    {
      enabled: !!currentAccount?.address,
      refetchInterval: 10000, // Refetch every 10 seconds
    },
  );

  // USDC has 6 decimals, convert from smallest unit to readable format
  const balance = balanceData?.totalBalance
    ? Number(balanceData.totalBalance) / 1e6
    : 0;

  const formattedBalance = balance.toLocaleString(undefined, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 6,
  });

  return {
    balance,
    formattedBalance,
    rawBalance: balanceData?.totalBalance || "0",
    isLoading,
    error,
    refetch,
  };
}

