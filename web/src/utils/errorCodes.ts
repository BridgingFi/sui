/**
 * Error code mappings for Volo Vault contracts
 * Based on error codes defined in volo_vault.move, operation.move, oracle.move, etc.
 */

// Error codes from volo_vault.move (5xxx range)
export const VOLO_VAULT_ERROR_CODES: Record<number, string> = {
  5001: "Exceed limit",
  5002: "Vault ID mismatch",
  5003: "Receipt ID mismatch",
  5004: "Zero share",
  5005: "Vault not enabled",
  5006: "Vault receipt not match",
  5007: "USD value not updated within the update interval",
  5008: "Exceed loss limit",
  5009: "Unexpected slippage",
  5010: "Request not found",
  5011: "Asset type already exists",
  5012: "Asset type not found",
  5013: "Invalid version",
  5014: "Reward manager already set",
  5015: "Operator is frozen",
  5016: "Coin buffer not found",
  5017: "Wrong receipt status",
  5018: "Request cancel time not reached",
  5019: "Exceed receipt shares",
  5020: "Receipt not found",
  5021: "Insufficient claimable principal",
  5022: "Vault is not in normal state",
  5023: "Recipient mismatch",
  5024: "Vault not during operation",
  5025: "Vault during operation",
  5026: "Invalid coin asset type",
  5027: "Operation value update not enabled",
  5028: "No free principal",
};

// Error codes from operation.move (1xxx range)
export const OPERATION_ERROR_CODES: Record<number, string> = {
  1001: "Verify share failed",
  1002: "Assets length mismatch",
  1003: "Assets not returned",
  1004: "Vault ID mismatch",
};

// Error codes from oracle.move (2xxx range)
export const ORACLE_ERROR_CODES: Record<number, string> = {
  2001: "Aggregator not found for coin type",
  2002: "Aggregator price not updated within the update interval",
  2003: "Aggregator already exists",
  2004: "Aggregator asset mismatch",
  2005: "Invalid version of oracle config",
};

// Error codes from reward_manager.move (3xxx range)
export const REWARD_MANAGER_ERROR_CODES: Record<number, string> = {
  3001: "Reward manager vault mismatch",
  3002: "Reward exceed limit",
  3003: "Reward buffer type exists",
  3004: "Reward buffer type not found",
  3005: "Remaining reward in buffer",
  3006: "Wrong receipt status",
  3007: "Invalid version",
  3008: "Insufficient reward amount",
  3009: "Invalid reward rate",
  3010: "Vault has no shares",
  3011: "Reward type not found",
  3012: "Reward amount too small",
};

// Error codes from user_entry.move (4xxx range)
export const USER_ENTRY_ERROR_CODES: Record<number, string> = {
  4001: "Insufficient balance",
  4002: "Vault ID mismatch",
  4003: "Withdraw locked",
  4004: "Invalid amount",
};

// Combined error code map
export const ALL_ERROR_CODES: Record<number, string> = {
  ...VOLO_VAULT_ERROR_CODES,
  ...OPERATION_ERROR_CODES,
  ...ORACLE_ERROR_CODES,
  ...REWARD_MANAGER_ERROR_CODES,
  ...USER_ENTRY_ERROR_CODES,
};

/**
 * Parse transaction error and return user-friendly message
 * @param err - Error object from transaction
 * @returns User-friendly error message
 */
export function parseTransactionError(err: unknown): string {
  if (!err) {
    return String(err);
  }

  // Debug: Log error structure to understand actual format
  // eslint-disable-next-line no-console
  console.log("Transaction error:", err);

  // TODO: Handle abortCode from Move contract errors
  // According to Sui SDK ExecutionError structure:
  // - For Move abort errors: errorDetails.oneofKind === 'abort' and errorDetails.abort.abortCode (bigint)
  // - The error might be wrapped in Error object from useSignAndExecuteTransaction
  // - Check errorObj.cause or errorObj.details for ExecutionError structure
  // - abortCode is of type bigint in MoveAbort interface
  // When abortCode is found, convert to number and use ALL_ERROR_CODES mapping

  const { code, message: msg } = err as Record<string, unknown>;

  // Check code first, then format with message if available
  if (code != null) {
    return msg ? `${msg} (code: ${code})` : `Error code: ${code}`;
  }

  // Fallback to message or string representation
  return String(msg ?? err);
}
