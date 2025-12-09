/**
 * Repayment mode enum
 * Defines the different modes of the repayment flow and request types
 */
export enum RepaymentMode {
  /** No request data, operator initiates */
  INIT = 0,
  /** Has request data, repayer supplies coins */
  SUPPLY_COINS = 1,
  /** Has signed transaction, operator executes */
  EXECUTE = 2,
}

/**
 * Parameters for SUPPLY_COINS mode
 * Used when operator initiates a repayment request
 * Note: assetType is in the URL path, not in params
 */
export interface SupplyCoinsParams {
  operatorCapId: string;
  /** Operator's address (sender, pays gas) */
  operatorAddress: string;
  /** Amount in human-readable format (e.g., "100.5") */
  amount: string;
}

/**
 * Parameters for EXECUTE mode
 * Extends supply coins parameters with transaction signature data
 * Used when repayer shares signed transaction with operator
 */
export interface ExecuteParams extends SupplyCoinsParams {
  /** Transaction digest/hash */
  txHash: string;
  /** Repayer's signature (base64 encoded) */
  signature: string;
  /** Optional: coin operation data for precise reconstruction */
  coinIds: string;
}

/**
 * Parsed repayment data from URL parameters
 */
export type ParsedRepaymentData =
  | { mode: RepaymentMode.SUPPLY_COINS; params: SupplyCoinsParams }
  | { mode: RepaymentMode.EXECUTE; params: ExecuteParams }
  | { mode: RepaymentMode.INIT };

/**
 * Parse repayment data from search params
 * @param searchParams - URLSearchParams from useSearchParams hook
 * @returns ParsedRepaymentData with type classification
 * @throws Error if required parameters are missing for a detected type
 */
export function parseRepaymentData(
  searchParams: URLSearchParams,
): ParsedRepaymentData {
  // Check if search params are empty
  if (searchParams.size === 0) {
    return { mode: RepaymentMode.INIT };
  }

  // Extract all parameters
  const txHash = searchParams.get("txHash");
  const signature = searchParams.get("signature");
  const operatorCapId = searchParams.get("operatorCapId");
  const operatorAddress = searchParams.get("operatorAddress");
  const amount = searchParams.get("amount");
  const coinIds = searchParams.get("coinIds");

  // Validate all common parameters are present
  if (!operatorCapId) {
    throw new Error("Missing operatorCapId parameter");
  }
  if (!operatorAddress) {
    throw new Error("Missing operatorAddress parameter");
  }
  if (!amount) {
    throw new Error("Missing amount parameter");
  }

  const baseData: SupplyCoinsParams = {
    operatorCapId,
    operatorAddress,
    amount,
  };

  // Check if this is a signed transaction (has txHash or signature)
  if (txHash || signature) {
    // If any signedTx-specific param is present, all must be present
    if (!txHash) {
      throw new Error("Missing txHash parameter for signed transaction");
    }
    if (!signature) {
      throw new Error("Missing signature parameter for signed transaction");
    }
    if (!coinIds) {
      throw new Error("Missing coinIds parameter for signed transaction");
    }

    const signedTxData: ExecuteParams = {
      ...baseData,
      txHash,
      signature,
      coinIds,
    };

    return {
      mode: RepaymentMode.EXECUTE,
      params: signedTxData,
    };
  }

  // Otherwise, it's a repayment request
  return {
    mode: RepaymentMode.SUPPLY_COINS,
    params: baseData,
  };
}

/**
 * Build repayment URL
 * @param params - Repayment params
 * @param vaultId - Vault ID (from route or vault info)
 * @param assetType - Asset type (from route path)
 * @returns URL with query parameters
 */
export function buildRepaymentURL(
  params: ExecuteParams | SupplyCoinsParams,
  vaultId: string,
  assetType: string,
): string {
  const baseUrl = window.location.origin;
  const searchParams = new URLSearchParams(
    Object.entries(params).filter(([_, value]) => value != null),
  );

  return `${baseUrl}/vault/${vaultId}/${encodeURIComponent(assetType)}/repay?${searchParams.toString()}`;
}

/**
 * Extract key information from dryrun result for display
 * @param dryrunResult - Dry run transaction block response
 * @returns Extracted information object
 */
export function extractDryrunInfo(dryrunResult: {
  effects?: {
    gasUsed?: {
      computationCost?: string;
      storageCost?: string;
      storageRebate?: string;
    };
    status?: {
      status?: string;
      error?: string;
    };
  };
  events?: Array<{
    type?: string;
    parsedJson?: unknown;
  }>;
  objectChanges?: Array<{
    type?: string;
    objectId?: string;
  }>;
}) {
  return {
    gasUsed: dryrunResult.effects?.gasUsed,
    status: dryrunResult.effects?.status,
    events: dryrunResult.events,
    objectChanges: dryrunResult.objectChanges,
  };
}
