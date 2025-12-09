# BridgingFi Vault Technical Design

**Last Updated**: 2025-11-25

## Overview

- Provide a minimum viable Sui vault experience reusing the audited `volo_vault` package without modification.
- Support end-user deposit and withdraw flows for any `CoinType` that the upstream vault supports (USDC on testnet for the demo).
- Keep project-specific logic in a thin wrapper so upgrades can happen independently of the upstream contracts.

## Move Package Layout

**Package**: `move/vault`

### Module: `bridgingfi_vault::vault_registry`

**Purpose**: Registry for tracking all vault instances in the system.

**Functions**:

- `create_registry` - Create the vault registry (one-time setup, creates shared object)
- `register_vault_by_id<CoinType>` - Register a vault to the registry (admin only)
- `get_all_vaults` - Get all registered vaults (view function)
- `get_vault_info` - Get vault info by vault ID (view function)
- `vault_count` - Get the number of registered vaults (view function)
- `get_admin` - Get the admin address (view function)

**Design**: Shared object (`VaultRegistry`) stores a `VecMap<address, VaultInfo>` mapping vault IDs to registration information. Admin address is stored in the registry and checked for registration operations.

### Module: `bridgingfi_vault::vault_proxy` ⚠️ **Not currently used, may not be needed**

**Functions** (if used):

- `deposit_new_receipt<CoinType>` - Create new receipt
- `deposit_with_receipt<CoinType>` - Top up existing receipt
- `request_withdraw_auto_transfer<CoinType>` - Request withdrawal

**Design**: Uses `std::option` to toggle between `None` and `Some(receipt)` because Move 2024 forbids `Option` parameters in `entry` functions.

**Note**: Currently, frontend directly calls `volo_vault::user_entry` functions. The proxy layer may not be necessary.

## External Dependencies

- The demo targets Sui testnet USDC at `0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC`.
  - Can be swapped at https://testnet.flowx.finance/swap

### volo_vault Package Dependency

`volo_vault` must be published as a local dependency to obtain independent `AdminCap` ownership. The `volo_vault::vault::init()` function transfers `AdminCap` to the package publisher, and `create_vault()` requires `AdminCap` to create Vault instances.

- Managed via Git Subtree (see `move/local_dependencies/README.md` for setup and update instructions).
- Development uses local path dependency; deployment uses network-specific branches with published addresses.
- **Only depends on Switchboard** (via local dependency), simplifying deployment. Volo Vault has been streamlined to remove DeFi protocol adapters (Navi, Suilend, Cetus, etc.) while maintaining core functionality.

See `move/local_dependencies/README.md` for deployment instructions.

## Transaction Flows

- **Deposit (new receipt)**: Forward to Volo helper with `None` receipt
- **Deposit (existing receipt)**: Forward with `Some(receipt)`
- **Withdraw**: Call Volo withdraw helper, preserve queue semantics

**Note**: Wrapper does not manage pause flags, admin queues, or profit ledgers (deferred to future iterations).

## BridgingFi Position Adapter

**Module**: `volo_vault::bridgingfi_adapter` (in local dependencies)

**Purpose**: Custom adapter for off-chain investments (UK lending market) with APR-based debt calculation.

### Core Functions

**Public Functions**:

- `create_position` - Create BridgingFiPosition (operator only)
- `update_value` - Update USD value based on compound interest (anyone can call)

**Operator Functions** (require OperatorCap):

- `repay` - Repay debt to vault
- `deploy_to_custodian` - Transfer funds to custodian account
- `update_custodian` - Update custodian account address

### Repayment Flow

The repayment flow supports multi-signature transactions:

1. **Operator Init** (`RepaymentMode.INIT`):
   - Operator selects OperatorCap and amount
   - Generates shareable URL with parameters

2. **Repayer** (`RepaymentMode.SUPPLY_COINS`):
   - Receives request URL
   - Builds transaction (using operator's OperatorCap)
   - Simulates transaction (dry run)
   - Signs transaction
   - Generates signed transaction URL

3. **Operator Execute** (`RepaymentMode.EXECUTE`):
   - Receives signed transaction URL
   - Rebuilds transaction with same parameters
   - Verifies transaction hash consistency
   - Signs and executes with merged signatures

**Route**: `/vault/:vaultId/:assetType/repay`

**Implementation**: `web/src/routes/repayment.tsx`

## Deployment Notes

- Publish the Move package to Sui testnet and record the resulting module IDs.
- Store published addresses in frontend environment variables (e.g., `VITE_VAULT_PACKAGE_ID`) and script config (e.g., `VAULT_PACKAGE_ID`).
- Helper scripts are under `move/vault/scripts`.
