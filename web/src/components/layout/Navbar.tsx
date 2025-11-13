import {
  Button,
  Dropdown,
  DropdownItem,
  DropdownMenu,
  DropdownTrigger,
  Link,
  Navbar as HeroNavbar,
  NavbarBrand,
  NavbarContent,
  NavbarItem,
  Image,
} from '@heroui/react';
import { NavArrowDown, Xmark } from 'iconoir-react';
import { useState } from 'react';
import { useLocation } from 'react-router-dom';

import { routes } from '@/lib/siteConfig';
import { WalletConnectButtonWithModal } from '@/components/wallet/WalletConnectButtonWithModal';

export const Navbar = () => {
  const { pathname } = useLocation();
  const [isOpen, setIsOpen] = useState(false);

  const isVault = pathname === '/';
  const isAdmin = pathname === '/admin';
  const currentPage = isVault ? 'Vault' : 'Admin';

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

      <NavbarContent className="basis-1/5" justify="center">
        {/* Mobile dropdown selector */}
        <NavbarItem className="sm:hidden">
          <Dropdown isOpen={isOpen} placement="bottom-start" onOpenChange={setIsOpen}>
            <DropdownTrigger>
              <Button
                endContent={isOpen ? <Xmark /> : <NavArrowDown />}
                size="lg"
                variant="light"
              >
                {currentPage}
              </Button>
            </DropdownTrigger>
            <DropdownMenu aria-label="Navigation menu">
              {routes.map((item) => (
                <DropdownItem key={item.href} as={Link} href={item.href}>
                  {item.label}
                </DropdownItem>
              ))}
            </DropdownMenu>
          </Dropdown>
        </NavbarItem>
      </NavbarContent>

      <NavbarContent className="hidden sm:flex basis-1/5" justify="center">
        <NavbarItem>
          <Button
            as={Link}
            className="min-w-16"
            color={isVault ? 'primary' : 'default'}
            href="/"
            size="sm"
            variant={isVault ? 'solid' : 'light'}
          >
            Vault
          </Button>
        </NavbarItem>
        <NavbarItem>
          <Button
            as={Link}
            className="min-w-16"
            color={isAdmin ? 'primary' : 'default'}
            href="/admin"
            size="sm"
            variant={isAdmin ? 'solid' : 'light'}
          >
            Admin
          </Button>
        </NavbarItem>
      </NavbarContent>

      <NavbarContent className="flex basis-1/5" justify="end">
        <NavbarItem>
          <WalletConnectButtonWithModal />
        </NavbarItem>
      </NavbarContent>
    </HeroNavbar>
  );
};
