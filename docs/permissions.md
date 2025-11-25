# Permission System

**Last Updated**: 2025-11-25

## Overview

This document describes where AdminCap and OperatorCap permissions are required in the system.

## AdminCap Requirements

**Location**: `volo_vault::vault_manage` module

- `create_operator_cap` - Create new OperatorCap objects
- `set_operator_freezed` - Freeze/unfreeze OperatorCaps
- `add_switchboard_aggregator` - Add aggregator to OracleConfig
- `remove_switchboard_aggregator` - Remove aggregator from OracleConfig
- `change_switchboard_aggregator` - Replace aggregator in OracleConfig
- `set_update_interval` - Update OracleConfig update interval
- `set_dex_slippage` - Update OracleConfig DEX slippage
- `set_vault_enabled` - Enable/disable vault
- `set_deposit_fee` - Set vault deposit fee
- `set_withdraw_fee` - Set vault withdraw fee
- `set_loss_tolerance` - Set vault loss tolerance
- `set_locking_time_for_cancel_request` - Set cancel request locking time
- `set_locking_time_for_withdraw` - Set withdraw locking time
- `reset_loss_tolerance` - Reset vault loss tolerance
- `retrieve_deposit_withdraw_fee` - Retrieve collected fees
- `create_reward_manager` - Create reward manager for vault

**Location**: `volo_vault::vault` module

- `create_vault` - Create new vault instance (requires AdminCap from package publisher)

**Location**: `bridgingfi_vault::vault_registry` module

- `register_vault_by_id` - Register a vault to the registry (requires registry admin)

## OperatorCap Requirements

**Location**: `volo_vault::operation` module

- `execute_deposit` - Execute deposit requests
- `execute_withdraw` - Execute withdraw requests
- `cancel_deposit` - Cancel deposit requests
- `cancel_withdraw` - Cancel withdraw requests
- `start_operation` - Start vault operation (borrow assets, principal)
- `end_operation` - End vault operation (return assets, principal)
- `check_value_update` - Check operation value update

**Location**: `volo_vault::vault_manage` module

- `retrieve_deposit_withdraw_fee_operator` - Retrieve collected fees (operator version)

**Note**: OperatorCap must not be freezed (checked in Move contracts).

## Permission Verification

All permission checks are enforced in Move contracts:

- AdminCap ownership verified via `has_key` check
- OperatorCap ownership and freezed status verified in contract functions
- No client-side permission checks provide security (UX-only)

## Related Documentation

- **Move Contracts**: `move/local_dependencies/volo-smart-contracts/volo-vault/sources/`
  - `vault::AdminCap`, `vault::OperatorCap` - Permission objects
  - `vault_manage::*` - Admin functions
  - `operation::*` - Operator functions
- **Project Modules**: `move/vault/sources/vault_registry.move`
