# Volo Vault Overview

This document provides a quick overview of Volo Vault core concepts and key interfaces for understanding the system context.

## Core Modules

### `volo_vault::vault`

**Purpose**: Core vault implementation managing deposits, shares, withdrawal queues, and asset values.

**Key Struct**: `Vault<PrincipalCoinType>`

- Tracks total shares, free/claimable principal
- Manages deposit/withdraw request buffers
- Stores asset values in USD
- Maintains receipt information

**Key Functions**:

- `create_vault<PrincipalCoinType>(_: &AdminCap, ctx)` - Create new vault (requires AdminCap)
- `request_deposit(...)` - Create deposit request
- `request_withdraw(...)` - Create withdraw request
- `update_free_principal_value(...)` - Update principal asset USD value via oracle

### `volo_vault::user_entry`

**Purpose**: User-facing entry points for deposits and withdrawals.

**Key Functions**:

- `deposit_with_auto_transfer<PrincipalCoinType>(...)` - Deposit with automatic receipt transfer
  - Accepts `Option<Receipt>` (None for new receipt, Some for existing)
  - Returns request ID
- `withdraw_with_auto_transfer<PrincipalCoinType>(...)` - Request withdrawal with automatic receipt transfer
- `cancel_deposit(...)` - Cancel pending deposit request
- `cancel_withdraw(...)` - Cancel pending withdraw request

**Note**: Move 2024 forbids `Option` parameters in `entry` functions, so these functions handle `Option<Receipt>` internally.

### `volo_vault::operation`

**Purpose**: Operator functions for executing requests and managing vault operations.

**Key Functions** (require `OperatorCap`):

- `execute_deposit<PrincipalCoinType>(...)` - Execute deposit request
- `execute_withdraw<PrincipalCoinType>(...)` - Execute withdraw request
- `cancel_user_deposit(...)` - Cancel user deposit request
- `cancel_user_withdraw(...)` - Cancel user withdraw request
- `start_operation(...)` - Start vault operation (borrow assets for investment)
- `end_operation(...)` - End vault operation (return assets)

### `volo_vault::vault_manage`

**Purpose**: Admin functions for vault configuration and management.

**Key Functions** (require `AdminCap`):

- `create_operator_cap(...)` - Create OperatorCap
- `set_operator_freezed(...)` - Freeze/unfreeze OperatorCap
- `add_switchboard_aggregator(...)` - Add oracle aggregator
- `remove_switchboard_aggregator(...)` - Remove oracle aggregator
- `set_update_interval(...)` - Set oracle update interval
- `set_deposit_fee(...)` / `set_withdraw_fee(...)` - Set fees

## Key Data Structures

### `Receipt`

User receipt object representing their position in the vault. Each receipt tracks:

- Shares owned
- Pending deposits/withdrawals
- Claimable principal

### `VaultReceiptInfo`

Internal vault state for each receipt:

- Status (NORMAL, PENDING_DEPOSIT, PENDING_WITHDRAW)
- Shares, pending balances
- Reward tracking

### `DepositRequest` / `WithdrawRequest`

Pending requests stored in vault's request buffer, awaiting operator execution.

## Permission System

Volo Vault uses two permission types:

- **`AdminCap`**: Administrative permissions for vault configuration (obtained from `vault::init()`)
- **`OperatorCap`**: Operational permissions for executing user requests (created by admin)

See `docs/permissions.md` for detailed permission requirements by function.

## Adapter Pattern

Volo Vault supports an adapter pattern for updating asset values without returning assets. This enables:

- **On-chain DeFi positions**: Read value from on-chain protocols
- **Off-chain investments**: Calculate value based on APR or other metrics

**How It Works**:

1. Custom adapter implements value calculation logic
2. Adapter calls `vault.finish_update_asset_value()` to update USD value
3. Share price reflects updated asset values
4. No asset return required - only value updates

**Current Status**: Built-in DeFi adapters (Navi, Suilend, Cetus) have been removed to simplify deployment. Custom adapters can be implemented when needed (see `architecture-plan.md` for future adapter strategy).

## Key Concepts

### Share Price Calculation

```
Share Ratio = Total USD Value / Total Shares
```

Total USD value includes:

- Principal coin value (updated via oracle)
- Other asset values (updated via adapters)

### Vault States

- **NORMAL** (0): Users can deposit/withdraw
- **DURING_OPERATION** (1): Assets borrowed for investment, users cannot deposit/withdraw
- **DISABLED** (2): Vault disabled

### Request Flow

1. **User Request**: User calls `deposit_with_auto_transfer` or `withdraw_with_auto_transfer`
2. **Request Created**: Vault creates request in buffer, returns request ID
3. **Operator Execution**: Operator calls `execute_deposit` or `execute_withdraw` with OperatorCap
4. **Completion**: Shares/coins transferred, events emitted

## External Dependencies

- **Switchboard**: Oracle for price feeds (only external dependency after adapter removal)
- **Clock**: `sui::clock::Clock` required for timed operations

## Related Documentation

- **Source Code**: `move/local_dependencies/volo-smart-contracts/volo-vault/sources/`
- **Permissions**: `docs/permissions.md` - Detailed permission requirements by function
- **Architecture Plan**: `docs/architecture-plan.md` - Future adapter implementation strategy
