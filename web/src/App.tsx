import { Route, Routes } from "react-router-dom";

import { AdminRoute } from "@/routes/admin";
import { HomeRoute } from "@/routes/home";
import { VaultDetailRoute } from "@/routes/vault-detail";

export default function App() {
  return (
    <Routes>
      <Route element={<HomeRoute />} path="/" />
      <Route element={<VaultDetailRoute />} path="/vault/:vaultId" />
      <Route element={<AdminRoute />} path="/admin" />
    </Routes>
  );
}
