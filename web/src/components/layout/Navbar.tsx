import {
  Dropdown,
  DropdownItem,
  DropdownMenu,
  DropdownTrigger,
  Navbar as HeroNavbar,
  NavbarBrand,
  NavbarContent,
  NavbarItem,
  NavbarMenu,
  NavbarMenuItem,
  NavbarMenuToggle,
  Image,
  Link,
  Button,
} from "@heroui/react";
import { useLocation } from "react-router-dom";
import { useState, useRef, useMemo } from "react";
import { NavArrowDown } from "iconoir-react";

import { WalletConnectButtonWithModal } from "@/components/wallet/WalletConnectButtonWithModal";
import { useManagePermission } from "@/hooks/useManagePermission";

export const Navbar = () => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isManageDropdownOpen, setIsManageDropdownOpen] = useState(false);
  const closeMenuAbortControllerRef = useRef<AbortController | null>(null);
  const location = useLocation();
  const { hasPermission, isLoading: isLoadingPermission } =
    useManagePermission();

  // Determine selected keys for dropdown menu
  const selectedKeys = useMemo(() => {
    const path = location.pathname;

    if (path === "/manage") {
      return ["vaults"];
    }

    if (path === "/manage/operator-caps") {
      return ["operator-caps"];
    }

    if (path === "/manage/oracle-config") {
      return ["oracle-config"];
    }

    return [];
  }, [location.pathname]);

  // Only show navigation links if user has AdminCap or OperatorCap
  const isManagePage =
    location.pathname === "/manage" || location.pathname.startsWith("/manage/");

  const handleMouseEnter = () => {
    // Cancel any pending close operation
    closeMenuAbortControllerRef.current?.abort();
    setIsManageDropdownOpen(true);
  };

  const handleMouseLeave = () => {
    // Cancel any existing timeout first (this implements debounce)
    closeMenuAbortControllerRef.current?.abort();
    // Create a new AbortController for this close operation
    const { signal } = (closeMenuAbortControllerRef.current =
      new AbortController());

    // Create a cancelable delay using setTimeout + AbortController
    const timeoutId = setTimeout(
      () => signal.aborted || setIsManageDropdownOpen(false),
      300,
    );

    // Clean up timeout if signal is aborted
    signal.addEventListener("abort", () => clearTimeout(timeoutId));
  };

  return (
    <HeroNavbar
      isMenuOpen={isMenuOpen}
      maxWidth="xl"
      position="static"
      onMenuOpenChange={setIsMenuOpen}
    >
      <NavbarContent>
        <NavbarMenuToggle
          aria-label={isMenuOpen ? "Close menu" : "Open menu"}
          className="sm:hidden"
        />
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

      <NavbarContent className="hidden gap-4 sm:flex" justify="center">
        {hasPermission && !isLoadingPermission && (
          <>
            <NavbarItem isActive={location.pathname === "/"}>
              <Link
                aria-current={location.pathname === "/" ? "page" : undefined}
                color={location.pathname === "/" ? "primary" : "foreground"}
                href="/"
              >
                Vault
              </Link>
            </NavbarItem>
            <NavbarItem isActive={isManagePage}>
              <Dropdown
                isOpen={isManageDropdownOpen}
                onOpenChange={setIsManageDropdownOpen}
              >
                <DropdownTrigger
                  onMouseEnter={handleMouseEnter}
                  onMouseLeave={handleMouseLeave}
                >
                  <Button
                    disableRipple
                    as={Link}
                    className="p-0 bg-transparent data-[hover=true]:bg-transparent"
                    color={isManagePage ? "primary" : "default"}
                    endContent={<NavArrowDown />}
                    href="/manage"
                    radius="sm"
                    variant="light"
                  >
                    Manage
                  </Button>
                </DropdownTrigger>
                <DropdownMenu
                  hideSelectedIcon
                  aria-label="Manage menu"
                  selectedKeys={selectedKeys}
                  selectionMode="single"
                  onMouseEnter={handleMouseEnter}
                  onMouseLeave={handleMouseLeave}
                >
                  <DropdownItem key="vaults" href="/manage">
                    Vaults
                  </DropdownItem>
                  <DropdownItem
                    key="operator-caps"
                    href="/manage/operator-caps"
                  >
                    OperatorCap
                  </DropdownItem>
                  <DropdownItem
                    key="oracle-config"
                    href="/manage/oracle-config"
                  >
                    Oracle Config
                  </DropdownItem>
                </DropdownMenu>
              </Dropdown>
            </NavbarItem>
          </>
        )}
      </NavbarContent>

      <NavbarContent justify="end">
        <NavbarItem>
          <WalletConnectButtonWithModal />
        </NavbarItem>
      </NavbarContent>

      <NavbarMenu>
        {hasPermission && !isLoadingPermission && (
          <>
            <NavbarMenuItem>
              <Link
                className="w-full"
                color={location.pathname === "/" ? "primary" : "foreground"}
                href="/"
                onPress={() => setIsMenuOpen(false)}
              >
                Vault
              </Link>
            </NavbarMenuItem>
            <NavbarMenuItem>
              <Link
                className="w-full"
                color={
                  location.pathname === "/manage" ? "primary" : "foreground"
                }
                href="/manage"
                onPress={() => setIsMenuOpen(false)}
              >
                Manage
              </Link>
            </NavbarMenuItem>
            <NavbarMenuItem>
              <Link
                className="w-full pl-4"
                color={
                  location.pathname === "/manage/operator-caps"
                    ? "primary"
                    : "foreground"
                }
                href="/manage/operator-caps"
                onPress={() => setIsMenuOpen(false)}
              >
                OperatorCap
              </Link>
            </NavbarMenuItem>
            <NavbarMenuItem>
              <Link
                className="w-full pl-4"
                color={
                  location.pathname === "/manage/oracle-config"
                    ? "primary"
                    : "foreground"
                }
                href="/manage/oracle-config"
                onPress={() => setIsMenuOpen(false)}
              >
                Oracle Config
              </Link>
            </NavbarMenuItem>
          </>
        )}
      </NavbarMenu>
    </HeroNavbar>
  );
};
