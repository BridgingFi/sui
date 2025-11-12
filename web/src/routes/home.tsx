import { Card, CardBody, CardHeader, Spacer } from '@heroui/react';

import { AppLayout } from '@/components/layout/AppLayout';

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

        <Card>
          <CardHeader>
            <h2 className="text-lg font-medium">Getting started</h2>
          </CardHeader>
          <CardBody className="space-y-4">
            <p>
              Connect your wallet to view vault metrics, make a deposit, or request a withdrawal.
            </p>
          </CardBody>
        </Card>

        <Spacer y={8} />
      </section>
    </AppLayout>
  );
};
