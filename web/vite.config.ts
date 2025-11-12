import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig(() => {
  return {
    define: {
      'import.meta.env.APP_VERSION': JSON.stringify(process.env.npm_package_version ?? '0.0.0'),
    },
    plugins: [react(), tsconfigPaths(), tailwindcss()],
  };
});
