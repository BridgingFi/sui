import { Route, Routes } from "react-router-dom";

import { ManageRoute } from "@/routes/manage";
import { HomeRoute } from "@/routes/home";
import { VaultDetailRoute } from "@/routes/vault-detail";
import { OperatorCapRoute } from "@/routes/operator-caps";

export default function App() {
  return (
    <Routes>
      <Route element={<HomeRoute />} path="/" />
      <Route element={<VaultDetailRoute />} path="/vault/:vaultId" />
      <Route element={<ManageRoute />} path="/manage/:vaultId?" />
      <Route element={<OperatorCapRoute />} path="/manage/operator-caps" />
    </Routes>
  );
}
