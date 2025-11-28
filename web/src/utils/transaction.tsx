import type { SuiClient } from "@mysten/sui/client";
import type { Transaction } from "@mysten/sui/transactions";
import type { DryRunTransactionBlockResponse } from "@mysten/sui/jsonRpc";

import { addToast, closeToast } from "@heroui/react";
import { toBase64 } from "@mysten/sui/utils";

import { ALL_ERROR_CODES } from "./errorCodes";

/**
 * Extract error information from transaction build errors
 * Specifically designed for errors with error.cause containing DryRunTransactionBlockResponse
 * Note: This does NOT handle JsonRpcError from dryRunTransactionBlock failures
 * Priority: abortError.error_code -> status.error -> err.message
 * @param err - Error object (typically from tx.build() with error.cause)
 * @returns Error code if found, error message otherwise
 */
export function extractTransactionErrorInfo(err: unknown): {
  errorCode?: number;
  errorMessage?: string;
} {
  if (err instanceof Error) {
    // Try to extract from error.cause (dryRunResult structure from dryRunTransactionBlock)
    // This only works for errors that have error.cause with DryRunTransactionBlockResponse
    if ("cause" in err && err.cause) {
      const cause = err.cause as DryRunTransactionBlockResponse;

      // First priority: abortError.error_code
      const errorCodeStr = cause.effects?.abortError?.error_code;

      if (errorCodeStr) {
        const code = parseInt(errorCodeStr, 10);

        if (!Number.isNaN(code) && code > 0) {
          return {
            errorCode: code,
            errorMessage: ALL_ERROR_CODES[code] || `Error code ${code}`,
          };
        }
      }

      // Second priority: status.error
      if (
        cause.effects?.status?.status !== "success" &&
        cause.effects?.status?.error
      ) {
        return {
          errorMessage: cause.effects.status.error,
        };
      }
    }

    // Fallback: err.message
    if (err.message) {
      return {
        errorMessage: err.message,
      };
    }
  }

  // No error information available
  return {};
}

/**
 * Analyze transaction by building it and extracting error information
 * This function is called when a transaction fails after being sent.
 * - If build fails: extracts error code/message from build error, logs and returns
 * - If build succeeds: the previous transaction already failed, but build succeeds here,
 *   so we cannot extract specific error details from the build result
 * Error extraction works in both dev and production, only base64 logging is dev-only
 * @param tx - The transaction to analyze
 * @param client - The Sui client instance
 * @param errorLog - Error logger function (required)
 * @returns Error information with optional error code and error message
 */
export async function analyzeTransaction(
  tx: Transaction,
  client: SuiClient,
  errorLog: (message: string, ...args: unknown[]) => void,
): Promise<{ errorCode?: number; errorMessage?: string }> {
  try {
    const txBytes = await tx.build({ client });

    // The previous transaction already failed, but build succeeds here,
    // so we cannot extract specific error details from the build result
    if (import.meta.env.DEV) {
      errorLog("Transaction bytes (base64): %s", toBase64(txBytes));
    }

    // Return undefined errorMessage to indicate we couldn't extract error details
    return {};
  } catch (buildErr) {
    // Extract error information
    const { errorCode, errorMessage } = extractTransactionErrorInfo(buildErr);

    errorLog(
      "Transaction error: %o, error code: %o, cause: %o",
      errorMessage,
      errorCode,
      buildErr,
    );

    return { errorCode, errorMessage };
  }
}

/**
 * Check if error should skip transaction analysis
 * Errors like user rejection don't need analysis
 * @param err - The error object
 * @returns true if analysis should be skipped
 */
function shouldSkipAnalysis(err: unknown): boolean {
  const errorMessage =
    err instanceof Error
      ? err.message.toLowerCase()
      : String(err).toLowerCase();

  // User rejection/cancellation errors
  const skipPatterns = ["duplicate", "rejected", "insufficient"];

  return skipPatterns.some((pattern) => errorMessage.includes(pattern));
}

/**
 * Handle transaction error with automatic error analysis and toast display
 * Shows an initial toast with error message and "Inspecting error details...",
 * then analyzes the transaction and shows a detailed error toast
 * For user rejection errors, skips analysis and shows error directly
 * @param err - The original error
 * @param tx - The transaction that failed
 * @param client - The Sui client instance
 * @param errorLog - Error logger function
 * @param title - Optional toast title (defaults to "Transaction failed")
 */
export function showTransactionErrorToast(
  err: unknown,
  tx: Transaction,
  client: SuiClient,
  errorLog: (message: string, ...args: unknown[]) => void,
  title: string = "Transaction failed",
): void {
  const errorMessage =
    err instanceof Error ? err.message : String(err ?? "Unknown error");

  errorLog("Transaction failed: %O", err);

  // Skip analysis for user rejection/cancellation errors
  if (shouldSkipAnalysis(err)) {
    addToast({
      title,
      description: errorMessage,
      color: "danger",
    });

    return;
  }

  const toastId = addToast({
    timeout: 0,
    title,
    description: `${errorMessage}(Inspecting error details...)`,
    color: "danger",
    promise: analyzeTransaction(tx, client, errorLog)
      .then((errorInfo) => {
        if (toastId) closeToast(toastId);
        addToast({
          title,
          description: (
            <>
              {errorMessage}
              {errorInfo.errorMessage && `, ${errorInfo.errorMessage}`}
              {errorInfo.errorCode && (
                <>
                  <br />
                  Error code: {errorInfo.errorCode}
                </>
              )}
            </>
          ),
          color: "danger",
        });
      })
      .catch((analyzeErr) => {
        errorLog("Failed to analyze transaction: %O", analyzeErr);
        if (toastId) closeToast(toastId);
        addToast({
          title,
          description: (
            <>
              {errorMessage}(Failed to analyze transaction)
              <br />
              {analyzeErr instanceof Error
                ? analyzeErr.message
                : String(analyzeErr)}
            </>
          ),
          color: "danger",
        });
      }),
  });
}
