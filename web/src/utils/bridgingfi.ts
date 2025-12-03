/**
 * Utility functions for BridgingFi adapter
 */

const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";

/**
 * Generate asset type string for BridgingFiPosition
 * This matches vault_utils::parse_key<BridgingFiPosition>(idx)
 * Format: type_name::get<BridgingFiPosition>().into_string() + idx.to_string()
 * Example: "volo_vault::bridgingfi_adapter::BridgingFiPosition0"
 * @param idx - Index of the position (default 0)
 */
export function parseBridgingFiAssetType(idx: number = 0): string {
  // vault_utils::parse_key returns: type_name + idx.to_string()
  // So for idx=0, it's "volo_vault::bridgingfi_adapter::BridgingFiPosition0"
  return `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition${idx}`;
}

/**
 * Convert APR from u256 decimal format to percentage string
 * APR is stored as: 5% = 50000000 (0.05 * 1e9)
 * @param aprDecimal - APR in u256 format (1e9 precision)
 * @returns Percentage string (e.g., "5.00%")
 */
export function formatAPR(aprDecimal: bigint): string {
  const percentage = (Number(aprDecimal) / 1e9) * 100;

  return `${percentage.toFixed(2)}%`;
}

/**
 * Convert day index to human-readable date string
 * Day index is days since Unix epoch (1970-01-01)
 * @param dayIndex - Day index (u64)
 * @returns Date string (e.g., "2025-01-15")
 */
export function formatDayIndex(dayIndex: number): string {
  if (dayIndex === 0) {
    return "Never";
  }

  const msPerDay = 24 * 60 * 60 * 1000;
  const timestamp = dayIndex * msPerDay;
  const date = new Date(timestamp);
  const dateStr = date.toISOString().split("T")[0];

  return dateStr || "Never";
}

/**
 * Calculate current debt using compound interest (client-side)
 * Formula: compounded_rate = (1 + apr/365) ^ days
 *         current_debt = outstanding_balance × compounded_rate
 *
 * This is a simplified client-side calculation for preview purposes.
 * For accurate calculations, use the on-chain get_current_debt function.
 *
 * @param outstandingBalance - Outstanding balance in coin units (u64)
 * @param aprDecimal - APR in u256 format (1e9 precision)
 * @param lastUpdateDay - Last update day index
 * @param currentDay - Current day index
 * @returns Current debt in coin units (approximate)
 */
export function calculateCurrentDebt(
  outstandingBalance: bigint,
  aprDecimal: bigint,
  lastUpdateDay: number,
  currentDay: number,
): bigint {
  if (outstandingBalance === 0n) {
    return 0n;
  }

  const days = currentDay - lastUpdateDay;

  if (days <= 0) {
    return outstandingBalance;
  }

  // Convert to JavaScript numbers for calculation (may lose precision for very large values)
  const balance = Number(outstandingBalance);
  const apr = Number(aprDecimal) / 1e9; // Convert from 1e9 format to decimal
  const ratePerDay = apr / 365;
  const base = 1 + ratePerDay;

  // Calculate compounded rate: base ^ days
  const compoundedRate = Math.pow(base, days);

  // Calculate current debt
  const currentDebt = balance * compoundedRate;

  return BigInt(Math.floor(currentDebt));
}

/**
 * Get current day index from current timestamp
 * @returns Current day index (days since Unix epoch)
 */
export function getCurrentDayIndex(): number {
  const msPerDay = 24 * 60 * 60 * 1000;
  const now = Date.now();

  return Math.floor(now / msPerDay);
}
