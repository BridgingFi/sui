import { Navbar } from './Navbar';

export const AppLayout = ({ children }: { children: React.ReactNode }) => {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <Navbar />
      <main className="container mx-auto flex w-full max-w-6xl grow flex-col px-6 py-10">
        {children}
      </main>
    </div>
  );
};
