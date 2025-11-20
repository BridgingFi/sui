import d from "debug";

/**
 * Initialize debug configuration
 * This function should be called once at application startup
 */
export function initDebug() {
  // Enable debug logs
  // Always enable error logs (err:* namespace), then add VITE_DEBUG if set
  const enabledNamespaces = ["err,err:*"];

  if (import.meta.env.VITE_DEBUG) {
    enabledNamespaces.push(import.meta.env.VITE_DEBUG);
  }

  d.enable(enabledNamespaces.join(","));
}

/**
 * Create debug and error loggers for a given namespace
 * @param namespace - The namespace for debug logs (e.g., "app:hooks:vault-requests")
 * @returns Object with:
 *   - `debugLog` - Regular debug logger using the provided namespace
 *   - `errorLog` - Error logger that automatically adds `err:` prefix to the namespace
 *                  (e.g., "app:hooks:vault-requests" becomes "err:app:hooks:vault-requests")
 *                  and is bound to console.error for always-on error logging
 */
export function loggers(namespace: string) {
  const debugLog = d(namespace);
  const errorLog = d(`err:${namespace}`);

  // Automatically bind error logger to console.error
  // eslint-disable-next-line no-console
  errorLog.log = console.error.bind(console);

  return {
    debugLog,
    errorLog,
  };
}
