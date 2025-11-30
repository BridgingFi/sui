# Frontend Data Sources

**Last Updated**: 2025-11-30

## Overview

This document describes where frontend data comes from - which data is read from on-chain objects, which from events, and which from GraphQL. This helps understand the data flow when starting from scratch.

---

## Data Sources

### On-Chain Objects (via Sui RPC)

- **Vault Registry** (`useVaultRegistry`)

  - Source: `bridgingfi_vault::vault_registry::VaultRegistry` object
  - Contains: List of registered vault IDs and metadata
  - Location: `web/src/hooks/useVaultRegistry.ts`

- **Vault Info** (`useVaultInfo`)

  - Source: `volo_vault::vault::Vault` object
  - Contains: `deposit_fee_rate`, `withdraw_fee_rate`, `total_shares`, `free_principal`, `claimable_principal`, `locking_time_for_withdraw`, `locking_time_for_cancel_request`, `asset_types`
  - Note: `share_ratio` is read from events (see below)
  - Location: `web/src/hooks/useVaultInfo.ts`

- **Oracle Config** (`useOracleConfig`)

  - Source: `volo_vault::vault_manage::OracleConfig` object
  - Contains: Switchboard aggregator list, update interval, DEX slippage
  - Location: `web/src/hooks/useOracleConfig.ts`

- **User Receipts** (`useUserReceipts`)

  - Source: User-owned `volo_vault::receipt::Receipt` objects
  - Contains: Receipt IDs and associated vault IDs
  - Location: `web/src/hooks/useUserReceipts.ts`

- **Receipt Details** (`useReceiptDetails`)

  - Source: Vault's receipt table (via `getDynamicFields` + `multiGetObjects`)
  - Contains: Receipt shares, pending deposits/withdrawals, claimable amounts
  - Location: `web/src/hooks/useReceiptDetails.ts`

- **Vault Requests** (`useVaultRequests`)

  - Source: Vault's `request_buffer` table (via `getDynamicFields` + `multiGetObjects`)
  - Contains: Pending deposit and withdraw requests
  - Location: `web/src/hooks/useVaultRequests.ts`

- **Vault Assets** (`useVaultAssets`)

  - Source: Vault's asset table (via `getDynamicFields` + `multiGetObjects`)
  - Contains: Asset balances by type
  - Location: `web/src/hooks/useVaultAssets.ts`

- **Permission Objects** (`useAdminCap`, `useOperatorCaps`)
  - Source: User-owned `volo_vault::vault::AdminCap` and `volo_vault::vault::OperatorCap` objects
  - Contains: Permission capabilities for management operations
  - Location: `web/src/hooks/useAdminCap.ts`, `web/src/hooks/useOperatorCaps.ts`

### Events (via GraphQL)

- **Share Ratio History** (`useVaultShareRatioHistoryGraphQL`)

  - Source: `ShareRatioUpdated` events via Sui GraphQL API
  - Contains: Historical share ratio changes with timestamps
  - Filter: Client-side filtering by `vault_id` (server filters by event type)
  - Pagination: Cursor-based with "load more" functionality
  - Location: `web/src/hooks/useVaultShareRatioHistoryGraphQL.ts`

- **Vault Share Ratio** (current, in `useVaultInfo`)
  - Source: Latest `ShareRatioUpdated` event for the vault
  - Note: Only used for display, not for deposit calculations
  - Location: `web/src/hooks/useVaultInfo.ts`

### GraphQL Objects

- **Switchboard Aggregators** (`useSwitchboardAggregators`)
  - Source: Sui GraphQL API `objects` query with type filter
  - Contains: Aggregator addresses, names, current values, timestamps
  - Pagination: Cursor-based
  - Location: `web/src/hooks/useSwitchboardAggregators.ts`

---

## Data Flow Summary

### Vault Overview

1. **Vault List**: Registry object → `useVaultRegistry`
2. **Vault Details**: Vault object → `useVaultInfo`
3. **Share Ratio**: Latest event → `useVaultInfo` (for display)
4. **Share Ratio History**: Events → `useVaultShareRatioHistoryGraphQL`
5. **Assets**: Vault asset table → `useVaultAssets`
6. **Requests**: Vault request_buffer table → `useVaultRequests`

### User Receipts

1. **User Receipts**: User-owned objects → `useUserReceipts`
2. **Receipt Details**: Vault receipt table → `useReceiptDetails`

### Management

1. **Permissions**: User-owned AdminCap/OperatorCap → `useAdminCap`/`useOperatorCaps`
2. **Oracle Config**: OracleConfig object → `useOracleConfig`
3. **Switchboard Aggregators**: GraphQL objects → `useSwitchboardAggregators`

---

## Related Documentation

- **Permissions**: `docs/permissions.md` - Which operations require AdminCap/OperatorCap
- **Move Contracts**: `move/local_dependencies/volo-smart-contracts/volo-vault/sources/`
- **Frontend Hooks**: `web/src/hooks/` - Implementation details
