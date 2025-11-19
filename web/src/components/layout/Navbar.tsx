import {
  Navbar as HeroNavbar,
  NavbarBrand,
  NavbarContent,
  NavbarItem,
  Image,
} from "@heroui/react";

import { WalletConnectButtonWithModal } from "@/components/wallet/WalletConnectButtonWithModal";

export const Navbar = () => {
  return (
    <HeroNavbar maxWidth="xl" position="static">
      <NavbarContent className="basis-1/5 sm:basis-full" justify="start">
        <NavbarBrand>
          <Image
            alt="Logo"
            className="h-5 w-11"
            radius="none"
            src="/logo.svg"
          />
          <Image
            alt="BridgingFi"
            className="h-4 w-24"
            radius="none"
            src="/brand_dark.svg"
          />
        </NavbarBrand>
      </NavbarContent>

      <NavbarContent className="flex basis-1/5" justify="end">
        <NavbarItem>
          <WalletConnectButtonWithModal />
        </NavbarItem>
      </NavbarContent>
    </HeroNavbar>
  );
};
