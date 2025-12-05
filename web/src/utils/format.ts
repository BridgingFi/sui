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
