import { useMemo } from "react";
import {
  Card,
  CardBody,
  CardHeader,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
  Chip,
  Tooltip,
} from "@heroui/react";
import { JsonTreeView } from "@ark-ui/react/json-tree-view";
import "@/styles/json-tree-view.css";
import { NavArrowRight } from "iconoir-react";

import { CopyButton } from "@/components/common/CopyButton";
import {
  formatCoinAmount,
  truncateAddress,
  truncateCoinType,
} from "@/utils/format";

interface DryrunResultViewProps {
  dryrunResult: {
    effects?: {
      status?: {
        status?: string;
        error?: string;
      };
      gasUsed?: {
        computationCost?: string;
        storageCost?: string;
        storageRebate?: string;
        nonRefundableStorageFee?: string;
      };
    };
    balanceChanges?: Array<{
      owner?: {
        AddressOwner?: string;
        ObjectOwner?: string;
        Shared?: { initial_shared_version?: number };
      };
      coinType?: string;
      amount?: string;
    }>;
    objectChanges?: Array<{
      type?: string;
      objectId?: string;
      owner?: {
        AddressOwner?: string;
        ObjectOwner?: string;
        Shared?: { initial_shared_version?: number };
      };
      objectType?: string;
      version?: string;
      previousVersion?: string;
    }>;
    events?: Array<{
      type?: string;
      transactionModule?: string;
      parsedJson?: Record<string, unknown>;
    }>;
  };
  coinDecimals?: number | null;
}

/**
 * Component to display dryrun transaction result in a user-friendly format
 * Similar to Sui Explorer's transaction detail view
 */
export function DryrunResultView({
  dryrunResult,
  coinDecimals = 9,
}: DryrunResultViewProps) {
  const status = dryrunResult.effects?.status?.status;
  const error = dryrunResult.effects?.status?.error;
  const gasUsed = dryrunResult.effects?.gasUsed;
  const balanceChanges = dryrunResult.balanceChanges || [];
  const objectChanges = dryrunResult.objectChanges || [];
  const events = dryrunResult.events || [];

  // Calculate total gas cost
  const totalGasCost = useMemo(() => {
    if (!gasUsed) return null;
    const computation = BigInt(gasUsed.computationCost || "0");
    const storage = BigInt(gasUsed.storageCost || "0");
    const rebate = BigInt(gasUsed.storageRebate || "0");
    const nonRefundable = BigInt(gasUsed.nonRefundableStorageFee || "0");

    return computation + storage - rebate + nonRefundable;
  }, [gasUsed]);

  // Format owner for display
  const formatOwner = (owner: {
    AddressOwner?: string;
    ObjectOwner?: string;
    Shared?: { initial_shared_version?: number };
  }): string => {
    if (owner.AddressOwner) {
      return truncateAddress(owner.AddressOwner);
    }
    if (owner.ObjectOwner) {
      return truncateAddress(owner.ObjectOwner);
    }
    if (owner.Shared) {
      return `Shared(${owner.Shared.initial_shared_version})`;
    }

    return "Unknown";
  };

  // Get coin decimals from coin type (default to 9 for SUI, 6 for USDC)
  const getCoinDecimals = (coinType?: string): number => {
    if (!coinType) return coinDecimals || 9;
    if (coinType.includes("sui::SUI")) return 9;
    if (coinType.includes("usdc::USDC")) return 6;

    return coinDecimals || 9;
  };

  // Format amount with sign
  const formatAmount = (amount: string, coinType?: string): string => {
    const amountBigInt = BigInt(amount);
    const decimals = getCoinDecimals(coinType);
    const formatted = formatCoinAmount(
      amountBigInt < 0 ? -amountBigInt : amountBigInt,
      decimals,
    );

    return amountBigInt < 0 ? `-${formatted}` : `+${formatted}`;
  };

  // Get coin name from coin type
  const getCoinName = (coinType?: string): string => {
    if (!coinType) return "Unknown";
    if (coinType.includes("sui::SUI")) return "SUI";
    if (coinType.includes("usdc::USDC")) return "USDC";

    // Extract coin name from type
    const match = coinType.match(/::(\w+)::/);

    return match?.[1] || truncateCoinType(coinType) || "Unknown";
  };

  // Format coin type with name: 0xea10...USDC or 0x2::sui::SUI (full display for short addresses)
  const formatCoinTypeWithName = (coinType: string): string => {
    // For short addresses like 0x2, display fully; for long addresses, truncate
    // Sui standard addresses are typically 0x2, 0x3, etc. (very short)
    // Custom addresses are 64 characters long (0x + 64 hex chars)
    if (coinType.length >= 64) {
      return truncateAddress(coinType);
    }

    return coinType;
  };

  // Format object type: 0xbbd1...257f::vault::Vault<...> (omit content inside <>)
  const formatObjectType = (objectType: string): string => {
    // Remove content inside <>
    const withoutGenerics = objectType.replace(/<[^>]*>/g, "<...>");
    // Extract address part and type part
    const parts = withoutGenerics.split("::");

    if (parts.length >= 3 && parts[0]) {
      const address = parts[0];
      const typePart = parts.slice(1).join("::");

      return `${truncateAddress(address)}::${typePart}`;
    }

    return truncateCoinType(withoutGenerics);
  };

  // Format event type: 0xbbd1....257f::vault::DefiAssetBorrowed
  const formatEventType = (
    eventType: string,
  ): {
    prefix: string;
    name: string;
  } => {
    const parts = eventType.split("::");

    if (parts.length >= 3 && parts[0] && parts[parts.length - 1]) {
      const address = parts[0];
      const name = parts[parts.length - 1]!;
      const middleParts = parts.slice(1, -1);

      return {
        prefix: `${truncateAddress(address)}::${middleParts.join("::")}`,
        name,
      };
    }

    const lastPart = eventType.split("::").pop();

    return {
      prefix: truncateCoinType(eventType),
      name: lastPart || "Unknown",
    };
  };

  return (
    <>
      {/* Balance Changes */}
      {balanceChanges.length > 0 && (
        <Card className="border border-default-200">
          <CardHeader className="items-center justify-between">
            Balance Changes
            <span className="text-sm text-default-500">
              {balanceChanges.length} change
              {balanceChanges.length !== 1 ? "s" : ""}
            </span>
          </CardHeader>
          <CardBody className="p-0">
            <Table
              aria-label="Balance Changes"
              classNames={{
                wrapper: ["p-0", "rounded-none"],
                th: ["first:rounded-s-none", "last:rounded-e-none"],
              }}
            >
              <TableHeader>
                <TableColumn>ID</TableColumn>
                <TableColumn>TYPE</TableColumn>
                <TableColumn>COIN</TableColumn>
                <TableColumn>AMOUNT</TableColumn>
              </TableHeader>
              <TableBody>
                {balanceChanges.map((change, index) => {
                  const owner = change.owner;
                  const ownerAddress =
                    owner?.AddressOwner ||
                    owner?.ObjectOwner ||
                    (owner?.Shared
                      ? `Shared(${owner.Shared.initial_shared_version})`
                      : "");
                  const amount = change.amount || "0";
                  const isNegative = amount.startsWith("-");

                  return (
                    <TableRow key={index}>
                      <TableCell>
                        <Tooltip
                          showArrow
                          classNames={{
                            content: "max-w-60 break-all font-mono",
                          }}
                          color="foreground"
                          content={ownerAddress}
                          delay={200}
                        >
                          <div className="flex items-center">
                            {ownerAddress && (
                              <>
                                <span className="font-mono text-sm">
                                  {truncateAddress(ownerAddress)}
                                </span>
                                <CopyButton value={ownerAddress} />
                              </>
                            )}
                          </div>
                        </Tooltip>
                      </TableCell>
                      <TableCell>
                        {owner?.AddressOwner
                          ? "Account"
                          : owner?.ObjectOwner
                            ? "Account"
                            : owner?.Shared
                              ? "Shared"
                              : "Unknown"}
                      </TableCell>
                      <TableCell>
                        {change.coinType && (
                          <Tooltip
                            showArrow
                            classNames={{
                              content: "max-w-sm break-all font-mono",
                            }}
                            color="foreground"
                            content={change.coinType}
                            delay={200}
                          >
                            <div className="flex items-center gap-2">
                              <span className="font-mono text-sm">
                                {formatCoinTypeWithName(change.coinType)}
                              </span>
                              <CopyButton
                                disableTooltip
                                value={change.coinType}
                              />
                            </div>
                          </Tooltip>
                        )}
                      </TableCell>
                      <TableCell>
                        <span
                          className={
                            isNegative ? "text-danger" : "text-success"
                          }
                        >
                          {formatAmount(amount, change.coinType)}
                        </span>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </CardBody>
        </Card>
      )}

      {/* Object Changes */}
      {objectChanges.length > 0 && (
        <Card className="border border-default-200">
          <CardHeader className="items-center justify-between">
            Object Changes
            <span className="text-sm text-default-500">
              {objectChanges.length} change
              {objectChanges.length !== 1 ? "s" : ""}
            </span>
          </CardHeader>
          <CardBody className="p-0">
            <Table
              aria-label="Object Changes"
              classNames={{
                wrapper: ["p-0", "rounded-none"],
                th: ["first:rounded-s-none", "last:rounded-e-none"],
              }}
            >
              <TableHeader>
                <TableColumn>OBJECT</TableColumn>
                <TableColumn>OWNER</TableColumn>
                <TableColumn>ACTION</TableColumn>
                <TableColumn>TYPE</TableColumn>
                <TableColumn>VERSION</TableColumn>
              </TableHeader>
              <TableBody>
                {objectChanges.map((change, index) => (
                  <TableRow key={index}>
                    <TableCell>
                      {change.objectId && (
                        <Tooltip
                          showArrow
                          classNames={{
                            content: "max-w-60 break-all font-mono",
                          }}
                          color="foreground"
                          content={change.objectId}
                          delay={200}
                        >
                          <div className="flex items-center">
                            <span className="font-mono text-sm">
                              {truncateAddress(change.objectId)}
                            </span>
                            <CopyButton
                              disableTooltip
                              value={change.objectId}
                            />
                          </div>
                        </Tooltip>
                      )}
                    </TableCell>
                    <TableCell>
                      {change.owner &&
                        (change.owner.AddressOwner ||
                        change.owner.ObjectOwner ? (
                          <Tooltip
                            showArrow
                            classNames={{
                              content: "max-w-60 break-all font-mono",
                            }}
                            color="foreground"
                            content={
                              change.owner.AddressOwner ||
                              change.owner.ObjectOwner
                            }
                            delay={200}
                          >
                            <div className="flex items-center">
                              <span className="font-mono text-sm">
                                {formatOwner(change.owner)}
                              </span>
                              <CopyButton
                                disableTooltip
                                value={
                                  change.owner.AddressOwner ||
                                  change.owner.ObjectOwner!
                                }
                              />
                            </div>
                          </Tooltip>
                        ) : (
                          <span className="font-mono text-sm">
                            {formatOwner(change.owner)}
                          </span>
                        ))}
                    </TableCell>
                    <TableCell>
                      <Chip
                        color={
                          change.type === "created"
                            ? "success"
                            : change.type === "mutated"
                              ? "warning"
                              : "default"
                        }
                        size="sm"
                        variant="flat"
                      >
                        {change.type === "created"
                          ? "Created"
                          : change.type === "mutated"
                            ? "Mutated"
                            : change.type || "Unknown"}
                      </Chip>
                    </TableCell>
                    <TableCell>
                      {change.objectType && (
                        <Tooltip
                          showArrow
                          classNames={{
                            content: "max-w-sm break-all font-mono",
                          }}
                          color="foreground"
                          content={change.objectType}
                          delay={200}
                        >
                          <div className="flex items-center gap-2">
                            <span className="font-mono text-xs">
                              {formatObjectType(change.objectType)}
                            </span>
                            <CopyButton
                              disableTooltip
                              value={change.objectType}
                            />
                          </div>
                        </Tooltip>
                      )}
                    </TableCell>
                    <TableCell>
                      {change.version && (
                        <span className="font-mono text-sm">
                          {change.version}
                        </span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardBody>
        </Card>
      )}

      {/* Events */}
      {events.length > 0 && (
        <Card className="border border-default-200">
          <CardHeader className="items-center justify-between">
            Events
            <span className="text-sm text-default-500">
              {events.length} event{events.length !== 1 ? "s" : ""}
            </span>
          </CardHeader>
          <CardBody className="space-y-3">
            {events.map((event, index) => {
              // Extract event name from type
              const eventType = event.type || "";
              const { prefix, name } = formatEventType(eventType);
              const module = event.transactionModule || "unknown";

              return (
                <div
                  key={index}
                  className="rounded-lg border border-default-200 pt-2 pb-4"
                >
                  <div className="flex items-baseline justify-between px-3 text-xs text-default-500">
                    <Tooltip
                      showArrow
                      color="foreground"
                      content={eventType}
                      delay={200}
                    >
                      <div className="flex items-baseline">
                        <span>{prefix}::</span>
                        <span className="text-sm text-foreground">{name}</span>
                      </div>
                    </Tooltip>
                    <span>{module}</span>
                  </div>
                  {event.parsedJson && (
                    <JsonTreeView.Root data={event.parsedJson}>
                      <JsonTreeView.Tree arrow={<NavArrowRight />} />
                    </JsonTreeView.Root>
                  )}
                </div>
              );
            })}
          </CardBody>
        </Card>
      )}
    </>
  );
}
