import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import tsconfigPaths from "vite-tsconfig-paths";
import { devtools } from "@tanstack/devtools-vite";

export default defineConfig(({ mode }) => {
  // Load environment variables using Vite's loadEnv
  // This correctly loads .env files based on mode (.env, .env.local, .env.[mode], .env.[mode].local)
  const env = loadEnv(mode, process.cwd(), "VITE_");

  // Check required environment variables at build time
  const requiredEnvVars = [
    "VITE_VAULT_PACKAGE_ID",
    "VITE_VAULT_REGISTRY_ID",
    "VITE_VOLO_VAULT_PACKAGE_ID_INITIAL",
    "VITE_VOLO_VAULT_PACKAGE_ID_LATEST",
    "VITE_VOLO_VAULT_ADMINCAP_ID",
    "VITE_VOLO_OPERATION_ID",
    "VITE_VOLO_ORACLE_CONFIG_ID",
    "VITE_SWITCHBOARD_AGGREGATOR_TYPE_ID",
    "VITE_SUI_GRAPHQL_URL",
  ];

  const missingVars = requiredEnvVars.filter((name) => !env[name]?.trim());

  if (missingVars.length > 0) {
    // eslint-disable-next-line no-console
    console.error(
      "❌ Missing required environment variables:",
      ...missingVars.map((name) => `\n- ${name}`),
    );
    process.exit(1);
  }

  return {
    define: {
      "import.meta.env.APP_VERSION": JSON.stringify(
        process.env.npm_package_version ?? "0.0.0",
      ),
    },
    plugins: [devtools(), react(), tsconfigPaths(), tailwindcss()],
  };
});
