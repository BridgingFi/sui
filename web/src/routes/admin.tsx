import { Card, CardBody, CardHeader } from '@heroui/react';

import { AppLayout } from '@/components/layout/AppLayout';

export const AdminRoute = () => {
  return (
    <AppLayout>
      <section className="space-y-6">
        <header className="space-y-2">
          <h1 className="text-3xl font-semibold">Admin Console</h1>
          <p className="text-default-500">
            Monitor queued deposits and withdrawals, and execute batched operations once the
            privileged tooling is connected.
          </p>
        </header>

        <Card>
          <CardHeader>
            <h2 className="text-lg font-medium">Coming soon</h2>
          </CardHeader>
          <CardBody>
            <p>
              The initial MVP focuses on end-user flows. Admin execution dashboards will be added in
              Phase 1.
            </p>
          </CardBody>
        </Card>
      </section>
    </AppLayout>
  );
};
