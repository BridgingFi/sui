import { Card, CardBody, CardHeader, Spacer } from '@heroui/react';

import { AppLayout } from '@/components/layout/AppLayout';
import { VaultList } from '@/components/vault/VaultList';

export const HomeRoute = () => {
  return (
    <AppLayout>
      <section className="space-y-8">
        <header className="space-y-2">
          <h1 className="text-3xl font-semibold">BridgingFi Vault</h1>
          <p className="text-default-500">
            Deposit Sui testnet USDC into the audited Volo vault integration and manage your
            receipts.
          </p>
        </header>

        <VaultList />

        <Spacer y={8} />
      </section>
    </AppLayout>
  );
};
