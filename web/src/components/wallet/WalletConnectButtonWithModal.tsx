import "@mysten/dapp-kit/dist/index.css";

import {
  Button,
  Dropdown,
  DropdownItem,
  DropdownMenu,
  DropdownTrigger,
} from "@heroui/react";
import {
  ConnectModal,
  useCurrentWallet,
  useCurrentAccount,
  useSwitchAccount,
  useDisconnectWallet,
} from "@mysten/dapp-kit";
import { NavArrowDown, Wallet, LogOut, Check } from "iconoir-react";
import { useCallback, useMemo, useState } from "react";

function truncateAddress(address: string): string {
  return `${address.slice(0, 4)}...${address.slice(-4)}`;
}

/**
 * Wallet connect button using ConnectModal from @mysten/dapp-kit.
 * This version uses the official ConnectModal for wallet selection,
 * but wraps it with HeroUI Button as the trigger.
 */
export function WalletConnectButtonWithModal() {
  const { currentWallet, isConnected } = useCurrentWallet();
  const currentAccount = useCurrentAccount();
  const { mutate: switchAccount } = useSwitchAccount();
  const { mutate: disconnect, isPending: isDisconnecting } =
    useDisconnectWallet();
  const [isDropdownOpen, setIsDropdownOpen] = useState(false);

  const handleDisconnect = useCallback(() => {
    disconnect();
    setIsDropdownOpen(false);
  }, [disconnect]);

  const handleSwitchAccount = useCallback(
    (account: NonNullable<typeof currentWallet>["accounts"][number]) => {
      if (!currentWallet) return;
      if (account.address === currentAccount?.address) {
        return;
      }
      switchAccount({ account });
      setIsDropdownOpen(false);
    },
    [currentAccount, switchAccount, currentWallet],
  );

  // Prepare data for menu items (must be before conditional return to follow Hooks rules)
  const accounts = currentWallet?.accounts || [];
  const hasMultipleAccounts = accounts.length > 1;

  const menuItems = useMemo(() => {
    const items = [];
    if (hasMultipleAccounts && currentWallet) {
      accounts.forEach((account) => {
        const isCurrentAccount = account.address === currentAccount?.address;
        items.push(
          <DropdownItem
            key={account.address}
            onPress={() => handleSwitchAccount(account)}
            startContent={isCurrentAccount ? <Check /> : undefined}
            className={isCurrentAccount ? "font-semibold" : ""}
          >
            {truncateAddress(account.address)}
          </DropdownItem>,
        );
      });
      items.push(
        <DropdownItem key="divider" isReadOnly className="h-0 p-0">
          <div className="h-px bg-default-200 my-1" />
        </DropdownItem>,
      );
    }
    items.push(
      <DropdownItem
        key="disconnect"
        className="text-danger"
        startContent={isDisconnecting ? undefined : <LogOut />}
        onPress={handleDisconnect}
      >
        {isDisconnecting ? "Disconnecting..." : "Disconnect"}
      </DropdownItem>,
    );
    return items;
  }, [
    accounts,
    currentAccount,
    currentWallet,
    hasMultipleAccounts,
    isDisconnecting,
    handleSwitchAccount,
    handleDisconnect,
  ]);

  // If not connected, show ConnectModal with HeroUI Button as trigger
  // Using uncontrolled mode so ConnectModal manages its own state
  if (!isConnected || !currentWallet) {
    return (
      <ConnectModal
        trigger={
          <Button color="primary" startContent={<Wallet />} variant="solid">
            Connect Wallet
          </Button>
        }
      />
    );
  }

  // If connected, show dropdown with wallet info
  const accountAddress =
    currentAccount?.address || currentWallet.accounts[0]?.address;

  return (
    <Dropdown isOpen={isDropdownOpen} onOpenChange={setIsDropdownOpen}>
      <DropdownTrigger>
        <Button
          color="primary"
          endContent={<NavArrowDown />}
          startContent={<Wallet />}
          variant="bordered"
        >
          {accountAddress ? truncateAddress(accountAddress) : "Connected"}
        </Button>
      </DropdownTrigger>
      <DropdownMenu aria-label="Wallet actions">{menuItems}</DropdownMenu>
    </Dropdown>
  );
}
