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

export function truncateCoinType(coinType: string): string {
  if (coinType.length <= 30) {
    return coinType;
  }

  return `${coinType.slice(0, 20)}...${coinType.slice(-10)}`;
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

/**
 * Format a coin amount with specified decimals
 * Handles bigint, string, or number input and formats with proper decimal places
 * Automatically trims trailing zeros from the decimal part
 * @param amount - The amount as bigint, string, or number (in smallest units)
 * @param decimals - Number of decimal places (e.g., 6 for USDC, 9 for SUI)
 * @returns Formatted string (e.g., "1234.567" or "1000" for whole numbers)
 */
export function formatCoinAmount(
  amount: bigint | string | number | null,
  decimals: number | null,
): string {
  if (amount === null || decimals === null) {
    return "N/A";
  }

  try {
    // Convert to bigint for consistent handling
    const amountBigInt =
      typeof amount === "bigint"
        ? amount
        : typeof amount === "string"
          ? BigInt(amount)
          : BigInt(Math.floor(amount));

    const divisor = BigInt(10 ** decimals);
    const wholePart = amountBigInt / divisor;
    const fractionalPart = amountBigInt % divisor;

    // If no fractional part, return whole number as string
    if (fractionalPart === 0n) {
      return wholePart.toString();
    }

    // Format fractional part with proper padding and trim trailing zeros
    const fractionalStr = fractionalPart.toString().padStart(decimals, "0");
    const trimmedFractional = fractionalStr.replace(/0+$/, "");

    return trimmedFractional.length > 0
      ? `${wholePart}.${trimmedFractional}`
      : wholePart.toString();
  } catch {
    return "N/A";
  }
}

/**
 * Convert a decimal string (e.g., "1.5") to a bigint with specified decimals
 * @param value - The decimal string value (e.g., "1.5")
 * @param decimals - The decimals multiplier (e.g., VAULT_DECIMALS = 10^9)
 * @returns The value as a string representing the bigint with decimals applied
 */
export function toDecimals(
  value: string,
  decimals: bigint = VAULT_DECIMALS,
): string {
  try {
    const num = Number(value);

    if (isNaN(num)) {
      return "0";
    }

    // Multiply by decimals to get the integer representation
    const decimalsNum = Number(decimals);
    const result = BigInt(Math.floor(num * decimalsNum));

    return result.toString();
  } catch {
    return "0";
  }
}
