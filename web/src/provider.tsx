import { ApolloClient, HttpLink, InMemoryCache } from "@apollo/client";
import { ApolloProvider } from "@apollo/client/react";
import { HeroUIProvider, ToastProvider } from "@heroui/react";
import {
  SuiClientProvider,
  WalletProvider,
  createNetworkConfig,
} from "@mysten/dapp-kit";
import { getFullnodeUrl } from "@mysten/sui/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useHref, useNavigate } from "react-router-dom";
import { TanStackDevtools } from "@tanstack/react-devtools";
import { ReactQueryDevtoolsPanel } from "@tanstack/react-query-devtools";

const queryClient = new QueryClient();

// Apollo Client for GraphQL queries
const GRAPHQL_URL = import.meta.env.VITE_SUI_GRAPHQL_URL;

const apolloClient = new ApolloClient({
  link: new HttpLink({ uri: GRAPHQL_URL }),
  cache: new InMemoryCache(),
  defaultOptions: {
    watchQuery: {
      errorPolicy: "all", // Return partial data even on errors
    },
    query: {
      errorPolicy: "all",
    },
  },
});

const { networkConfig } = createNetworkConfig({
  testnet: { url: getFullnodeUrl("testnet") },
});

export function Provider({ children }: { children: React.ReactNode }) {
  const navigate = useNavigate();

  return (
    <HeroUIProvider navigate={navigate} useHref={useHref}>
      <ToastProvider />
      <ApolloProvider client={apolloClient}>
        <QueryClientProvider client={queryClient}>
          <SuiClientProvider defaultNetwork="testnet" networks={networkConfig}>
            <WalletProvider autoConnect>{children}</WalletProvider>
          </SuiClientProvider>
          <TanStackDevtools
            plugins={[
              {
                name: "TanStack Query",
                render: <ReactQueryDevtoolsPanel />,
                defaultOpen: true,
              },
            ]}
          />
        </QueryClientProvider>
      </ApolloProvider>
    </HeroUIProvider>
  );
}
