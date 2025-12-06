module volo_vault::bridgingfi_adapter;

use std::ascii::String;
use std::type_name;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::object::{Self, UID};
use sui::transfer;
use sui::tx_context::TxContext;
use volo_vault::vault::{Self, Operation, OperatorCap, Vault};
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

// --------------------- Constants ---------------------//

const MS_PER_DAY: u64 = 24 * 3600 * 1000; // milliseconds per day
const DAYS_PER_YEAR: u64 = 365; // days per year
const U64_MAX: u256 = 18446744073709551615; // maximum value for u64

// --------------------- Errors ---------------------//

const ERR_CUSTODIAN_ACCOUNT_MISMATCH: u64 = 6_002;
const ERR_INSUFFICIENT_BALANCE: u64 = 6_003;
const ERR_VAULT_ID_MISMATCH: u64 = 6_004;

// --------------------- Structs ---------------------//

public struct BridgingFiPosition has key, store {
  id: UID,
  vault_id: address,
  custodian_account: address,
  outstanding_balance: u64,
  apr_decimal: u256,
  last_update_day: u64,
}

// --------------------- Helper Functions ---------------------//

/// Convert timestamp (ms) to day index (days since Unix epoch 1970-01-01)
public fun get_day_index(timestamp_ms: u64): u64 {
  timestamp_ms / MS_PER_DAY
}

/// Fast exponentiation for fixed-point decimals (using vault_utils precision)
/// Reference: Suilend's pow implementation
public fun pow_d(base: u256, mut exp: u64): u256 {
  let mut cur_base = base;
  let mut result = vault_utils::to_decimals(1); // 1.0 in 1e9 format

  while (exp > 0) {
    if (exp % 2 == 1) {
      result = vault_utils::mul_d(result, cur_base);
    };
    cur_base = vault_utils::mul_d(cur_base, cur_base);
    exp = exp / 2;
  };

  result
}

/// Calculate current real-time debt using compound interest
/// Reference: Suilend's compound interest algorithm
/// Formula: compounded_rate = (1 + apr/365) ^ days
///         current_debt = outstanding_balance × compounded_rate
public fun get_current_debt(
  position: &BridgingFiPosition,
  clock: &Clock,
): u256 {
  let snapshot_debt = position.outstanding_balance() as u256;
  let apr_decimal = position.apr_decimal(); // already in 1e9 format
  let last_update_day = position.last_update_day();
  let current_day = get_day_index(clock.timestamp_ms());

  // Calculate days based on dayIndex
  let days = current_day - last_update_day;

  if (days == 0) {
    return snapshot_debt;
  };

  // Use vault_utils for compound interest calculation (reference: Suilend algorithm)
  // compounded_rate = (1 + apr/365) ^ days

  // 1. Calculate rate_per_day = apr / 365
  let days_per_year_decimal = vault_utils::to_decimals(DAYS_PER_YEAR as u256);
  let rate_per_day = vault_utils::div_d(apr_decimal, days_per_year_decimal);

  // 2. Calculate base = 1 + rate_per_day
  let one_decimal = vault_utils::to_decimals(1);
  let base = one_decimal + rate_per_day;

  // 3. Calculate compounded_rate = base ^ days (fast exponentiation)
  let compounded_rate = pow_d(base, days);

  // 4. Calculate current_debt = snapshot_debt * compounded_rate
  let snapshot_debt_decimal = vault_utils::to_decimals(snapshot_debt);
  let current_debt_decimal = vault_utils::mul_d(
    snapshot_debt_decimal,
    compounded_rate,
  );

  // 5. Convert back to normal value
  vault_utils::from_decimals(current_debt_decimal)
}

// --------------------- Public Functions ---------------------//

/// Create a new BridgingFiPosition
/// @param vault_id: The vault ID this position belongs to
/// @param custodian_account: The custodian account address (recipient of investment funds)
/// @param apr_decimal: Annual percentage rate in 1e9 format (e.g., 5% = 50000000)
public fun create_position(
  vault_id: address,
  custodian_account: address,
  apr_decimal: u256,
  ctx: &mut TxContext,
): BridgingFiPosition {
  BridgingFiPosition {
    id: object::new(ctx),
    vault_id,
    custodian_account,
    outstanding_balance: 0,
    apr_decimal,
    last_update_day: 0,
  }
}

/// Update the NAV value based on compound interest
/// Anyone can call this function to update the value
/// Note: This function does not modify the position state (outstanding_balance and last_update_day).
public fun update_value<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  config: &OracleConfig,
  clock: &Clock,
  asset_type: String,
) {
  // Get BridgingFiPosition from vault (read-only, no need to modify)
  let position = vault.get_defi_asset<PrincipalCoinType, BridgingFiPosition>(
    asset_type,
  );

  // Calculate current real-time debt (compound interest) in coin units
  let current_debt_coin = get_current_debt(position, clock);

  // Get principal coin price from oracle
  let principal_price = vault_oracle::get_normalized_asset_price(
    config,
    clock,
    type_name::get<PrincipalCoinType>().into_string(),
  );

  // Convert debt from coin units to USD value
  let current_debt_usd = vault_utils::mul_with_oracle_price(
    current_debt_coin,
    principal_price,
  );

  // Update USD value (using current real-time debt in USD)
  vault.finish_update_asset_value(
    asset_type,
    current_debt_usd,
    clock.timestamp_ms(),
  );
}

/// Repay funds to vault
/// Note: This function should be called within start_op/end_op (caller's responsibility) and pass position borrowed from vault via start_op
/// If repayment amount exceeds debt, the excess will be returned
public fun repay_to_vault<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  position: &mut BridgingFiPosition,
  mut coin: Coin<PrincipalCoinType>,
  amount: u64,
  clock: &Clock,
  ctx: &mut TxContext,
): Coin<PrincipalCoinType> {
  // Verify vault_id matches
  assert!(position.vault_id() == vault.vault_id(), ERR_VAULT_ID_MISMATCH);

  // Validate coin has sufficient balance
  assert!(coin::value(&coin) >= amount, ERR_INSUFFICIENT_BALANCE);

  // Calculate current real-time debt (compound interest)
  let current_debt = get_current_debt(position, clock) as u64;
  let repay_amount = amount;

  // Calculate actual repayment amount (not exceeding debt)
  let actual_repay_amount = if (repay_amount >= current_debt) {
    current_debt // Fully repaid, actual repayment = debt
  } else {
    repay_amount // Partial repayment
  };

  // Extract actual repayment amount
  let repay_coin = coin.split(actual_repay_amount, ctx);

  // Return repayment to vault's free_principal
  // This is correct because:
  // 1. invest_to_custodian borrows from free_principal
  // 2. repay_to_vault should return to free_principal
  // 3. This allows the funds to be borrowed again for future investments
  vault.return_free_principal(repay_coin.into_balance());

  // Update outstanding_balance = current real-time debt - actual repayment amount
  let new_debt = current_debt - actual_repay_amount;
  position.set_outstanding_balance(new_debt);

  // Update last_update_day = current dayIndex
  let current_day = get_day_index(clock.timestamp_ms());
  position.update_last_update_day(current_day);

  // Return remaining coin (if any)
  coin
}

// --------------------- Operator Functions ---------------------//

/// Invest funds to custodian account
/// Note: This function should be called within start_op/end_op (caller's responsibility)
/// @param custodian_account: Secondary confirmation address (must match position's custodian_account)
public fun invest_to_custodian<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  position: &mut BridgingFiPosition,
  principal_balance: &mut Balance<PrincipalCoinType>,
  amount: u64,
  custodian_account: address,
  clock: &Clock,
  ctx: &mut TxContext,
) {
  // Verify the passed address matches the address in position
  assert!(
    custodian_account == position.custodian_account(),
    ERR_CUSTODIAN_ACCOUNT_MISMATCH,
  );

  // Validate amount
  assert!(
    balance::value(principal_balance) >= amount,
    ERR_INSUFFICIENT_BALANCE,
  );

  // Calculate current real-time debt first (if there is old debt, include compound interest)
  let current_debt = get_current_debt(position, clock) as u64;

  // Extract funds from principal_balance
  let transfer_balance = balance::split(principal_balance, amount);
  let transfer_coin = coin::from_balance(transfer_balance, ctx);

  // Transfer to custodian account (verified)
  transfer::public_transfer(transfer_coin, custodian_account);

  // Update outstanding_balance = current real-time debt + new principal
  let new_debt = current_debt + amount;
  position.set_outstanding_balance(new_debt);

  // Update last_update_day = current dayIndex
  let current_day = get_day_index(clock.timestamp_ms());
  position.update_last_update_day(current_day);
}

/// Update custodian account
/// Note: This function should be called within start_op/end_op (caller's responsibility)
public fun update_custodian_account<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  position: &mut BridgingFiPosition,
  new_custodian_account: address,
) {
  // Verify vault_id matches
  assert!(position.vault_id() == vault.vault_id(), ERR_VAULT_ID_MISMATCH);

  // Update custodian_account
  position.set_custodian_account(new_custodian_account);
}

// --------------------- Getters ---------------------//

public fun vault_id(position: &BridgingFiPosition): address {
  position.vault_id
}

public fun custodian_account(position: &BridgingFiPosition): address {
  position.custodian_account
}

public fun outstanding_balance(position: &BridgingFiPosition): u64 {
  position.outstanding_balance
}

public fun apr_decimal(position: &BridgingFiPosition): u256 {
  position.apr_decimal
}

public fun last_update_day(position: &BridgingFiPosition): u64 {
  position.last_update_day
}

// --------------------- Setters ---------------------//

public(package) fun set_outstanding_balance(
  position: &mut BridgingFiPosition,
  balance: u64,
) {
  position.outstanding_balance = balance;
}

public(package) fun update_last_update_day(
  position: &mut BridgingFiPosition,
  day: u64,
) {
  position.last_update_day = day;
}

public(package) fun set_custodian_account(
  position: &mut BridgingFiPosition,
  account: address,
) {
  position.custodian_account = account;
}
