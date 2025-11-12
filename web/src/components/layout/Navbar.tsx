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
} from '@heroui/react';
import { Menu, NavArrowDown } from 'iconoir-react';
import { useMemo, useState } from 'react';
import { useLocation } from 'react-router-dom';

import { routes, siteConfig } from '@/lib/siteConfig';

export const Navbar = () => {
  const { pathname } = useLocation();
  const [isOpen, setIsOpen] = useState(false);

  const current = useMemo(() => {
    const fallback = routes[0] ?? { label: 'Home', href: '/' };
    return routes.find((route) => route.href === pathname) ?? fallback;
  }, [pathname]);

  return (
    <HeroNavbar maxWidth="xl" position="sticky">
      <NavbarContent className="basis-1/3 sm:basis-full" justify="start">
        <NavbarBrand className="gap-2">
          <Link className="font-semibold" color="foreground" href="/">
            {siteConfig.name}
          </Link>
        </NavbarBrand>
      </NavbarContent>

      <NavbarContent className="basis-1/3" justify="center">
        <NavbarItem className="sm:hidden">
          <Dropdown isOpen={isOpen} onOpenChange={setIsOpen}>
            <DropdownTrigger>
              <Button
                endContent={isOpen ? <Menu /> : <NavArrowDown />}
                size="sm"
                variant="light"
              >
                {current.label}
              </Button>
            </DropdownTrigger>
            <DropdownMenu aria-label="Main navigation">
              {routes.map((route) => (
                <DropdownItem key={route.href} as={Link} href={route.href}>
                  {route.label}
                </DropdownItem>
              ))}
            </DropdownMenu>
          </Dropdown>
        </NavbarItem>
      </NavbarContent>

      <NavbarContent className="hidden gap-2 sm:flex" justify="center">
        {routes.map((route) => {
          const isActive = pathname === route.href;
          return (
            <NavbarItem key={route.href}>
              <Button
                as={Link}
                color={isActive ? 'primary' : 'default'}
                href={route.href}
                size="sm"
                variant={isActive ? 'solid' : 'light'}
              >
                {route.label}
              </Button>
            </NavbarItem>
          );
        })}
      </NavbarContent>

      <NavbarContent className="basis-1/3" justify="end">
        <NavbarItem className="hidden gap-3 sm:flex">
          <Link isExternal href={siteConfig.links.github} title="GitHub">
            GitHub
          </Link>
          <Link isExternal href={siteConfig.links.docs} title="Docs">
            Docs
          </Link>
        </NavbarItem>
      </NavbarContent>
    </HeroNavbar>
  );
};
