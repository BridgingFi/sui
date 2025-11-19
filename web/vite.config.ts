import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import tsconfigPaths from "vite-tsconfig-paths";

export default defineConfig(({ mode }) => {
  // Load environment variables using Vite's loadEnv
  // This correctly loads .env files based on mode (.env, .env.local, .env.[mode], .env.[mode].local)
  const env = loadEnv(mode, process.cwd(), "VITE_");

  // Check required environment variables at build time
  const requiredEnvVars = ["VITE_VAULT_PACKAGE_ID", "VITE_VAULT_REGISTRY_ID"];

  const missingVars: string[] = [];
  requiredEnvVars.forEach((varName) => {
    if (!env[varName] || env[varName]?.trim() === "") {
      missingVars.push(varName);
    }
  });

  if (missingVars.length > 0) {
    console.error("\n❌ Missing required environment variables:");
    missingVars.forEach((varName) => {
      console.error(`   - ${varName}`);
    });
    process.exit(1);
  }

  return {
    define: {
      "import.meta.env.APP_VERSION": JSON.stringify(
        process.env.npm_package_version ?? "0.0.0",
      ),
    },
    plugins: [react(), tsconfigPaths(), tailwindcss()],
  };
});
