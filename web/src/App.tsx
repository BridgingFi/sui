import { Route, Routes } from 'react-router-dom';

import { AdminRoute } from '@/routes/admin';
import { HomeRoute } from '@/routes/home';

export default function App() {
  return (
    <Routes>
      <Route element={<HomeRoute />} path="/" />
      <Route element={<AdminRoute />} path="/admin" />
    </Routes>
  );
}
