module volo_vault::bridgingfi_adapter;

use std::ascii::String;
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::{Self, Coin};
use sui::object::{Self, UID};
use sui::transfer;
use sui::tx_context::TxContext;
use volo_vault::vault::{Self, Vault};
use volo_vault::vault_oracle::OracleConfig;
use volo_vault::vault_utils;

// --------------------- Constants ---------------------//

const MS_PER_DAY: u64 = 24 * 3600 * 1000; // milliseconds per day
const DAYS_PER_YEAR: u64 = 365; // days per year
const U64_MAX: u256 = 18446744073709551615; // maximum value for u64

// --------------------- Errors ---------------------//

const ERR_OVERFLOW: u64 = 6_001;
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
public fun update_value<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  config: &OracleConfig,
  clock: &Clock,
  asset_type: String,
) {
  // Borrow BridgingFiPosition from vault
  let mut position = vault.borrow_defi_asset<
    PrincipalCoinType,
    BridgingFiPosition,
  >(
    asset_type,
  );

  // Calculate current real-time debt (compound interest)
  let current_debt = get_current_debt(&position, clock);

  // Update USD value (using current real-time debt)
  vault.finish_update_asset_value(
    asset_type,
    current_debt,
    clock.timestamp_ms(),
  );

  // Update outstanding_balance = current real-time debt (snapshot)
  // Overflow check: ensure current_debt can be converted to u64
  assert!(current_debt <= U64_MAX, ERR_OVERFLOW);
  position.set_outstanding_balance(current_debt as u64);

  // Update last_update_day = current dayIndex
  let current_day = get_day_index(clock.timestamp_ms());
  position.update_last_update_day(current_day);

  // Return BridgingFiPosition to vault
  vault.return_defi_asset(asset_type, position);
}

/// Repay funds to vault
/// Anyone can call this function to repay
/// If repayment amount exceeds debt, the excess will be returned to the caller
public fun repay_to_vault<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  asset_type: String,
  mut coin: Coin<PrincipalCoinType>,
  amount: u64,
  clock: &Clock,
  ctx: &mut TxContext,
): Coin<PrincipalCoinType> {
  // Validate amount
  assert!(coin.value() >= amount, ERR_INSUFFICIENT_BALANCE);

  // Borrow BridgingFiPosition from vault
  let mut position = vault.borrow_defi_asset<
    PrincipalCoinType,
    BridgingFiPosition,
  >(
    asset_type,
  );

  // Verify vault_id matches
  assert!(position.vault_id() == vault.vault_id(), ERR_VAULT_ID_MISMATCH);

  // Calculate current real-time debt (compound interest)
  let current_debt = get_current_debt(&position, clock);
  let repay_amount = amount as u256;

  // Calculate actual repayment amount (not exceeding debt)
  let actual_repay_amount = if (repay_amount >= current_debt) {
    current_debt // Fully repaid, actual repayment = debt
  } else {
    repay_amount // Partial repayment
  };

  // Calculate remaining amount (to be returned)
  let remaining_amount = repay_amount - actual_repay_amount;

  // Extract actual repayment amount
  let repay_coin = coin.split(actual_repay_amount as u64, ctx);

  // Inject into vault's free_principal
  vault.add_claimable_principal(repay_coin.into_balance());

  // Update outstanding_balance = current real-time debt - actual repayment amount
  let new_debt = current_debt - actual_repay_amount;
  // Overflow check: ensure new_debt can be converted to u64
  assert!(new_debt <= U64_MAX, ERR_OVERFLOW);
  position.set_outstanding_balance(new_debt as u64);

  // Update last_update_day = current dayIndex
  let current_day = get_day_index(clock.timestamp_ms());
  position.update_last_update_day(current_day);

  // Return BridgingFiPosition to vault
  vault.return_defi_asset(asset_type, position);

  // If there is remaining amount, merge it back to coin and return
  if (remaining_amount > 0) {
    let remaining_coin = coin.split(remaining_amount as u64, ctx);
    coin.join(remaining_coin);
  };

  coin
}

// --------------------- Package Functions (Operator Only) ---------------------//

/// Invest funds to custodian account
/// Requires operator permission (called via operation module)
/// @param custodian_account: Secondary confirmation address (must match position's custodian_account)
public(package) fun invest_to_custodian<PrincipalCoinType>(
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
  let current_debt = get_current_debt(position, clock);

  // Extract funds from principal_balance
  let transfer_balance = balance::split(principal_balance, amount);
  let transfer_coin = coin::from_balance(transfer_balance, ctx);

  // Transfer to custodian account (verified)
  transfer::public_transfer(transfer_coin, custodian_account);

  // Update outstanding_balance = current real-time debt + new principal
  let new_debt = current_debt + (amount as u256);
  // Overflow check: ensure new_debt can be converted to u64
  assert!(new_debt <= U64_MAX, ERR_OVERFLOW);
  position.set_outstanding_balance(new_debt as u64);

  // Update last_update_day = current dayIndex
  let current_day = get_day_index(clock.timestamp_ms());
  position.update_last_update_day(current_day);
}

/// Update custodian account
/// Requires operator permission
public(package) fun update_custodian_account<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  asset_type: String,
  new_custodian_account: address,
  ctx: &mut TxContext,
) {
  // Borrow BridgingFiPosition from vault
  let mut position = vault.borrow_defi_asset<
    PrincipalCoinType,
    BridgingFiPosition,
  >(
    asset_type,
  );

  // Verify vault_id matches
  assert!(position.vault_id() == vault.vault_id(), ERR_VAULT_ID_MISMATCH);

  // Update custodian_account
  position.set_custodian_account(new_custodian_account);

  // Return BridgingFiPosition to vault
  vault.return_defi_asset(asset_type, position);
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
