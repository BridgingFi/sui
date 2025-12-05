import {
  Button,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Input,
  Spinner,
  Table,
  TableBody,
  TableCell,
  TableColumn,
  TableHeader,
  TableRow,
} from "@heroui/react";
import { Search, NavArrowLeft, NavArrowRight } from "iconoir-react";
import { useState, useMemo } from "react";
import dayjs from "dayjs";
import relativeTime from "dayjs/plugin/relativeTime";

import { CopyButton } from "@/components/common/CopyButton";
import { useSwitchboardAggregatorsList } from "@/hooks/useSwitchboardAggregators";

dayjs.extend(relativeTime);

const PAGE_SIZE = 20;

function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

function formatValue(value: string, decimals: number = 18): string {
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
}

function formatTimestamp(timestampMs: string): string {
  try {
    const timestamp = parseInt(timestampMs, 10);

    if (timestamp === 0) {
      return "Never";
    }

    const date = dayjs(timestamp);

    if (!date.isValid()) {
      return "Never";
    }

    return date.fromNow();
  } catch {
    return "Unknown";
  }
}

interface SwitchboardAggregatorBrowserProps {
  onSelect?: (aggregatorId: string) => void;
}

/**
 * Component to browse and select Switchboard Aggregators
 */
export function SwitchboardAggregatorBrowser({
  onSelect,
}: SwitchboardAggregatorBrowserProps) {
  const [cursor, setCursor] = useState<string | null>(null);
  const [cursors, setCursors] = useState<Array<string | null>>([]);
  const [searchQuery, setSearchQuery] = useState("");

  const { aggregators, isLoading, isFetching, error, pagination } =
    useSwitchboardAggregatorsList({
      limit: PAGE_SIZE,
      cursor,
    });

  const filteredAggregators = useMemo(() => {
    if (!searchQuery.trim()) {
      return aggregators;
    }

    const query = searchQuery.toLowerCase();

    return aggregators.filter(
      (agg) =>
        agg.name.toLowerCase().includes(query) ||
        agg.address.toLowerCase().includes(query),
    );
  }, [aggregators, searchQuery]);

  // Handle pagination
  const handleNextPage = () => {
    if (pagination.nextCursor) {
      setCursors([...cursors, cursor]);
      setCursor(pagination.nextCursor);
    }
  };

  const handlePreviousPage = () => {
    if (cursors.length > 0) {
      const newCursors = [...cursors];

      newCursors.pop();
      setCursors(newCursors);

      setCursor(
        newCursors.length > 0
          ? (newCursors[newCursors.length - 1] ?? null)
          : null,
      );
    } else {
      setCursor(null);
    }
  };

  // Reset pagination when search query changes
  const handleSearchChange = (value: string) => {
    setSearchQuery(value);
    // Note: Search is client-side, so we don't reset pagination
    // If you want server-side search, you'd reset cursor here
  };

  if (isLoading) {
    return (
      <Card>
        <CardBody>
          <div className="flex items-center justify-center py-8">
            <Spinner size="lg" />
          </div>
        </CardBody>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardBody>
          <div className="text-danger">
            Error loading aggregators: {error.message}
          </div>
        </CardBody>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex w-full items-center justify-between">
          <h2 className="text-lg font-semibold">Switchboard Aggregators</h2>
          <Input
            className="w-64"
            placeholder="Search by name or address..."
            startContent={<Search className="w-4 h-4" />}
            value={searchQuery}
            onValueChange={handleSearchChange}
          />
        </div>
      </CardHeader>
      <Divider />
      <CardBody className="p-0">
        {filteredAggregators.length === 0 ? (
          <div className="py-8 px-4 text-center text-default-500">
            {searchQuery
              ? "No aggregators found on this page"
              : "No aggregators available"}
            {searchQuery && pagination.hasNextPage && (
              <p className="text-sm mt-2">
                Try loading the next page - there might be matching results.
              </p>
            )}
          </div>
        ) : (
          <div className="max-h-96 overflow-y-auto">
            <Table
              aria-label="Switchboard Aggregators"
              classNames={{
                wrapper: ["p-0", "rounded-none"],
                th: ["first:rounded-s-none", "last:rounded-e-none"],
              }}
            >
              <TableHeader>
                <TableColumn>Name</TableColumn>
                <TableColumn>Address</TableColumn>
                <TableColumn>Current Value</TableColumn>
                <TableColumn>Last Updated</TableColumn>
                <TableColumn>Actions</TableColumn>
              </TableHeader>
              <TableBody>
                {filteredAggregators.map((aggregator) => (
                  <TableRow key={aggregator.address}>
                    <TableCell>{aggregator.name}</TableCell>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        <span>{truncateAddress(aggregator.address)}</span>
                        <CopyButton disableTooltip value={aggregator.address} />
                      </div>
                    </TableCell>
                    <TableCell>
                      {aggregator.current_result
                        ? formatValue(aggregator.current_result.result.value)
                        : "N/A"}
                    </TableCell>
                    <TableCell>
                      {aggregator.current_result
                        ? formatTimestamp(
                            aggregator.current_result.timestamp_ms,
                          )
                        : "N/A"}
                    </TableCell>
                    <TableCell>
                      {onSelect && (
                        <Button
                          color="primary"
                          size="sm"
                          variant="flat"
                          onPress={() => onSelect(aggregator.address)}
                        >
                          Select
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
        {/* Pagination controls - always show if there's pagination available */}
        {(pagination.hasNextPage || cursors.length > 0) && (
          <div className="mt-4 flex items-center justify-between">
            <div className="text-sm text-default-500">
              {filteredAggregators.length > 0 ? (
                <>
                  Showing {filteredAggregators.length} aggregator
                  {filteredAggregators.length !== 1 ? "s" : ""}
                  {searchQuery && " (filtered)"}
                </>
              ) : (
                <>
                  {searchQuery
                    ? "No matches on this page"
                    : "No aggregators on this page"}
                </>
              )}
            </div>
            <div className="flex gap-2">
              <Button
                isDisabled={cursors.length === 0}
                isLoading={isFetching}
                size="sm"
                variant="flat"
                onPress={handlePreviousPage}
              >
                <NavArrowLeft className="w-4 h-4" />
                Previous
              </Button>
              <Button
                isDisabled={!pagination.hasNextPage}
                isLoading={isFetching}
                size="sm"
                variant="flat"
                onPress={handleNextPage}
              >
                Next
                <NavArrowRight className="w-4 h-4" />
              </Button>
            </div>
          </div>
        )}
      </CardBody>
    </Card>
  );
}
