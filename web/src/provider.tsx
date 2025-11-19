import { HeroUIProvider, ToastProvider } from "@heroui/react";
import {
  SuiClientProvider,
  WalletProvider,
  createNetworkConfig,
} from "@mysten/dapp-kit";
import { getFullnodeUrl } from "@mysten/sui/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useHref, useNavigate } from "react-router-dom";

const queryClient = new QueryClient();

const { networkConfig } = createNetworkConfig({
  testnet: { url: getFullnodeUrl("testnet") },
});

export function Provider({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();

  return (
    <HeroUIProvider navigate={navigate} useHref={useHref}>
      <ToastProvider />
      <QueryClientProvider client={queryClient}>
        <SuiClientProvider defaultNetwork="testnet" networks={networkConfig}>
          <WalletProvider>{children}</WalletProvider>
        </SuiClientProvider>
      </QueryClientProvider>
    </HeroUIProvider>
  );
}
