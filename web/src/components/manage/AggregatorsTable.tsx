import type { PriceInfo } from "@/lib/types";

import { useMemo } from "react";
import dayjs from "dayjs";
import relativeTime from "dayjs/plugin/relativeTime";
dayjs.extend(relativeTime);

import {
  Button,
  ButtonGroup,
  Link,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
  Tooltip,
} from "@heroui/react";
import { CloudSync, EditPencil, InfoCircle, Trash } from "iconoir-react";

import { CopyButton } from "@/components/common/CopyButton";
import { useSwitchboardAggregatorsByAddresses } from "@/hooks/useSwitchboardAggregators";
import { truncateAddress, truncateAssetType } from "@/utils/format";

interface AggregatorsTableProps {
  aggregatorsArray: Array<[string, PriceInfo]>;
  oracleConfig: {
    update_interval: number;
  } | null;
  hasAdminCap: boolean;
  isUpdating: boolean;
  updatingAssetType: string | null;
  isRemoving: boolean;
  removingAssetType: string | null;
  onUpdatePrice: (assetType: string, aggregatorId: string) => void;
  onChangeAggregator: (assetType: string) => void;
  onRemoveAggregator: (assetType: string) => void;
  formatDuration: (ms: number) => string;
}

export function AggregatorsTable({
  aggregatorsArray,
  oracleConfig,
  hasAdminCap,
  isUpdating,
  updatingAssetType,
  isRemoving,
  removingAssetType,
  onUpdatePrice,
  onChangeAggregator,
  onRemoveAggregator,
  formatDuration,
}: AggregatorsTableProps) {
  const formatValue = (value: string, decimals: number): string => {
    try {
      const bigIntValue = BigInt(value);
      const divisor = BigInt(10 ** decimals);
      const quotient = bigIntValue / divisor;
      const remainder = bigIntValue % divisor;

      if (remainder === BigInt(0)) {
        return quotient.toString();
      }

      const decimalPart = remainder.toString().padStart(decimals, "0");
      const trimmedDecimal = decimalPart.replace(/0+$/, "");

      return `${quotient}.${trimmedDecimal}`;
    } catch {
      return value;
    }
  };

  const formatTimestamp = (timestampMs: number): string => {
    try {
      const date = dayjs(timestampMs);

      if (!date.isValid()) {
        return "Unknown";
      }

      return date.fromNow();
    } catch {
      return "Unknown";
    }
  };

  // Check if price update is overdue
  const isPriceOverdue = (
    lastUpdated: number,
    updateInterval: number,
  ): boolean => {
    const now = Date.now();
    const diffMs = now - lastUpdated;

    return diffMs > updateInterval;
  };

  // Extract all aggregator addresses
  const aggregatorAddresses = useMemo(
    () => aggregatorsArray.map(([, priceInfo]) => priceInfo.aggregator),
    [aggregatorsArray],
  );

  // Batch fetch all switchboard aggregator data
  const { data: switchboardDataMap, isLoading: isLoadingSwitchboard } =
    useSwitchboardAggregatorsByAddresses(aggregatorAddresses);

  const switchboardNetwork = import.meta.env.VITE_SUI_NETWORK || "testnet";

  if (aggregatorsArray.length === 0) {
    return (
      <div className="py-8 px-4 text-center text-default-500">
        No aggregators configured
      </div>
    );
  }

  return (
    <Table
      aria-label="Configured Aggregators"
      classNames={{
        wrapper: ["p-0", "rounded-none"],
        th: ["first:rounded-s-none", "last:rounded-e-none"],
      }}
    >
      <TableHeader>
        <TableColumn>Asset Type</TableColumn>
        <TableColumn>Decimals</TableColumn>
        <TableColumn>Switchboard Aggregator</TableColumn>
        <TableColumn>Oracle Price</TableColumn>
        <TableColumn>Actions</TableColumn>
      </TableHeader>
      <TableBody>
        {aggregatorsArray.map(([assetType, priceInfo]) => {
          const switchboardData =
            switchboardDataMap.get(priceInfo.aggregator) || null;
          const switchboardFeedUrl = `https://ondemand.switchboard.xyz/sui/${switchboardNetwork}/feed/${priceInfo.aggregator}`;

          // Format tooltip content for switchboard timestamp
          const switchboardTooltipContent = switchboardData?.timestamp_ms
            ? `${dayjs(switchboardData.timestamp_ms).format("YYYY-MM-DD HH:mm:ss")} (UTC)\nTimestamp: ${switchboardData.timestamp_ms}`
            : "";

          // Format tooltip content for oracle timestamp
          const utcTime = dayjs(priceInfo.last_updated).format(
            "YYYY-MM-DD HH:mm:ss",
          );
          let oracleTooltipContent = `${utcTime} (UTC)\nTimestamp: ${priceInfo.last_updated}`;

          if (
            oracleConfig &&
            isPriceOverdue(priceInfo.last_updated, oracleConfig.update_interval)
          ) {
            oracleTooltipContent += `\nOverdue (Update interval: ${formatDuration(oracleConfig.update_interval)})`;
          }

          return (
            <TableRow key={assetType}>
              <TableCell className="align-top">
                <div className="flex items-center">
                  <span>{truncateAssetType(assetType)}</span>
                  <CopyButton disableTooltip value={assetType} />
                </div>
              </TableCell>
              <TableCell className="align-top">{priceInfo.decimals}</TableCell>
              <TableCell className="align-top">
                <div className="flex flex-col gap-2">
                  {/* Aggregator Address */}
                  <div className="flex items-center">
                    <Link isExternal href={switchboardFeedUrl} size="sm">
                      {truncateAddress(priceInfo.aggregator)}
                    </Link>
                    <CopyButton disableTooltip value={priceInfo.aggregator} />
                  </div>
                  {/* Switchboard Price */}
                  {isLoadingSwitchboard ? (
                    <Spinner size="sm" />
                  ) : (
                    <>
                      {switchboardData?.price && (
                        <div className="text-sm">
                          Price: {formatValue(switchboardData.price, 18)}
                        </div>
                      )}
                      {/* Switchboard Last Updated */}
                      {switchboardData?.timestamp_ms ? (
                        <div className="flex items-center gap-1">
                          Updated:{" "}
                          {formatTimestamp(switchboardData.timestamp_ms)}
                          {switchboardTooltipContent && (
                            <Tooltip
                              color="foreground"
                              content={switchboardTooltipContent}
                            >
                              <InfoCircle className="w-4 h-4 cursor-help" />
                            </Tooltip>
                          )}
                        </div>
                      ) : (
                        <span className="text-default-400 text-sm">
                          Updated: N/A
                        </span>
                      )}
                    </>
                  )}
                </div>
              </TableCell>
              <TableCell className="align-top">
                <div className="flex flex-col gap-2">
                  {/* Oracle Price */}
                  <div className="text-sm">
                    Price: {formatValue(priceInfo.price, 18)}
                  </div>
                  {/* Oracle Last Updated */}
                  <div className="flex items-center gap-1">
                    <span
                      className={
                        oracleConfig &&
                        isPriceOverdue(
                          priceInfo.last_updated,
                          oracleConfig.update_interval,
                        )
                          ? "text-danger text-sm"
                          : "text-sm"
                      }
                    >
                      Updated: {formatTimestamp(priceInfo.last_updated)}
                    </span>
                    <Tooltip color="foreground" content={oracleTooltipContent}>
                      <InfoCircle className="w-4 h-4 cursor-help" />
                    </Tooltip>
                  </div>
                </div>
              </TableCell>
              <TableCell className="align-top">
                <ButtonGroup color="primary" size="sm" variant="solid">
                  <Button
                    isIconOnly
                    isLoading={isUpdating && updatingAssetType === assetType}
                    onPress={() =>
                      onUpdatePrice(assetType, priceInfo.aggregator)
                    }
                  >
                    <CloudSync className="w-4 h-4" />
                  </Button>
                  {hasAdminCap && (
                    <>
                      <Button
                        isIconOnly
                        onPress={() => onChangeAggregator(assetType)}
                      >
                        <EditPencil className="w-4 h-4" />
                      </Button>
                      <Button
                        isIconOnly
                        color="danger"
                        isLoading={
                          isRemoving && removingAssetType === assetType
                        }
                        variant="flat"
                        onPress={() => onRemoveAggregator(assetType)}
                      >
                        <Trash className="w-4 h-4" />
                      </Button>
                    </>
                  )}
                </ButtonGroup>
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}
