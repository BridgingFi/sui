/**
 * Constants used across the application
 * These match the constants defined in Move contracts
 */

/**
 * Vault utils DECIMALS constant
 * Used for various calculations:
 * - share_price = share_ratio / DECIMALS
 * - div_d(v1, v2) = v1 * DECIMALS / v2
 * - mul_d(v1, v2) = v1 * v2 / DECIMALS
 * - from_decimals(v) = v / DECIMALS
 * - to_decimals(v) = v * DECIMALS
 * Matches: vault_utils::DECIMALS = 1_000_000_000
 */
export const VAULT_DECIMALS = BigInt(1e9);
