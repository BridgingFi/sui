import {
  Button,
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
} from "@heroui/react";
import { Link as RouterLink, useLocation, useNavigate } from "react-router-dom";
import { useState, useRef } from "react";
import { NavArrowDown } from "iconoir-react";

import { WalletConnectButtonWithModal } from "@/components/wallet/WalletConnectButtonWithModal";
import { useManagePermission } from "@/hooks/useManagePermission";

export const Navbar = () => {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isManageDropdownOpen, setIsManageDropdownOpen] = useState(false);
  const closeMenuAbortControllerRef = useRef<AbortController | null>(null);
  const location = useLocation();
  const navigate = useNavigate();
  const { hasPermission, isLoading: isLoadingPermission } =
    useManagePermission();

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
                as={RouterLink}
                color={location.pathname === "/" ? "primary" : "foreground"}
                to="/"
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
                    as={RouterLink}
                    className="p-0 bg-transparent data-[hover=true]:bg-transparent"
                    endContent={<NavArrowDown className="w-4 h-4" />}
                    radius="sm"
                    to="/manage"
                    variant="light"
                  >
                    Manage
                  </Button>
                </DropdownTrigger>
                <DropdownMenu
                  aria-label="Manage menu"
                  onMouseEnter={handleMouseEnter}
                  onMouseLeave={handleMouseLeave}
                >
                  <DropdownItem
                    key="vaults"
                    className={
                      location.pathname === "/manage" ? "bg-default-100" : ""
                    }
                    onPress={() => navigate("/manage")}
                  >
                    Vaults
                  </DropdownItem>
                  <DropdownItem
                    key="operator-caps"
                    className={
                      location.pathname === "/manage/operator-caps"
                        ? "bg-default-100"
                        : ""
                    }
                    onPress={() => navigate("/manage/operator-caps")}
                  >
                    OperatorCap
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
                as={RouterLink}
                className="w-full"
                color={location.pathname === "/" ? "primary" : "foreground"}
                to="/"
                onPress={() => setIsMenuOpen(false)}
              >
                Vault
              </Link>
            </NavbarMenuItem>
            <NavbarMenuItem>
              <Link
                as={RouterLink}
                className="w-full"
                color={
                  location.pathname === "/manage" ? "primary" : "foreground"
                }
                to="/manage"
                onPress={() => setIsMenuOpen(false)}
              >
                Manage
              </Link>
            </NavbarMenuItem>
            <NavbarMenuItem>
              <Link
                as={RouterLink}
                className="w-full pl-4"
                color={
                  location.pathname === "/manage/operator-caps"
                    ? "primary"
                    : "foreground"
                }
                to="/manage/operator-caps"
                onPress={() => setIsMenuOpen(false)}
              >
                OperatorCap
              </Link>
            </NavbarMenuItem>
          </>
        )}
      </NavbarMenu>
    </HeroNavbar>
  );
};
