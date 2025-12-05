import { VAULT_DECIMALS } from "@/lib/constants";

/**
 * Utility functions for formatting data
 */

/**
 * Truncate an address to show first 8 and last 6 characters
 * @param address - The address string to truncate
 * @returns Truncated address (e.g., "0x12345678...abcdef")
 */
export function truncateAddress(address: string): string {
  return `${address.slice(0, 8)}...${address.slice(-6)}`;
}

/**
 * Truncate an asset type string if it exceeds 30 characters
 * @param assetType - The asset type string to truncate
 * @returns Truncated asset type (e.g., "package::module...Name")
 */
export function truncateAssetType(assetType: string): string {
  if (assetType.length <= 30) {
    return assetType;
  }

  return `${assetType.slice(0, 20)}...${assetType.slice(-10)}`;
}

/**
 * Convert byte array (number[] or Uint8Array) to bigint
 * Converts to hex string first, then to bigint for simplicity
 * BCS uses little-endian, so we reverse the array before converting to hex
 * @param bytes - Byte array as number[] or Uint8Array (e.g., from returnValues[0][0])
 * @returns bigint value
 */
export function bytesToBigInt(bytes: number[] | Uint8Array): bigint {
  const uint8Array =
    bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes);

  // Convert to hex string: each byte to 2 hex characters
  // BCS uses little-endian, so reverse to get big-endian for BigInt
  const hex = Array.from(uint8Array)
    .reverse()
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return BigInt("0x" + hex);
}

/**
 * Convert a decimal value (u256 with DECIMALS) to a number
 * This is a generic conversion function - the caller should decide decimal places for display
 * @param value - The value as string or bigint (u256 from contract with DECIMALS)
 * @param decimals - The decimals divisor (default: VAULT_DECIMALS)
 * @returns The converted number
 */
export function fromDecimals(
  value: string | bigint | null,
  decimals: bigint = VAULT_DECIMALS,
): number {
  if (value === null) {
    return 0;
  }

  const valueBigInt = typeof value === "bigint" ? value : BigInt(value);
  const wholePart = valueBigInt / decimals;
  const remainder = valueBigInt % decimals;

  // Convert to number with decimal precision
  const wholeNum = Number(wholePart);
  const decimalPart = Number(remainder) / Number(decimals);

  return wholeNum + decimalPart;
}

/**
 * Format a decimal value (u256 with DECIMALS) for display
 * Generic formatting function that uses Intl.NumberFormatOptions
 * @param value - The value as string or bigint (u256 from contract with DECIMALS)
 * @param decimals - The decimals divisor (default: VAULT_DECIMALS)
 * @param options - Intl.NumberFormatOptions for formatting
 * @returns Formatted number string with decimals (e.g., "1,234.567890")
 */
export function formatDecimal(
  value: string | bigint,
  decimals: bigint = VAULT_DECIMALS,
  options?: Intl.NumberFormatOptions,
): string | undefined {
  try {
    const num = fromDecimals(value, decimals);

    return num.toLocaleString(undefined, options);
  } catch {
    return undefined;
  }
}
