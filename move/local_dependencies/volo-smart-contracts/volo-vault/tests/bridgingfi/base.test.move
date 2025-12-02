#[test_only]
module volo_vault::bridgingfi_base_test;

use sui::clock;
use sui::test_scenario;
use volo_vault::bridgingfi_adapter::{Self, BridgingFiPosition};
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::vault::{Vault, OperatorCap, Operation};
use volo_vault::vault_utils;

const OWNER: address = @0xa;
const CUSTODIAN: address = @0xb;
const APR_5_PERCENT: u256 = 50_000_000; // 5% in 1e9 format (0.05 * 1e9)
const APR_10_PERCENT: u256 = 100_000_000; // 10% in 1e9 format (0.10 * 1e9)
const APR_0_PERCENT: u256 = 0; // 0% APR
const APR_100_PERCENT: u256 = 1_000_000_000; // 100% in 1e9 format (1.0 * 1e9)
const INITIAL_INVESTMENT: u64 = 1_000_000_000; // 1 SUI

// ==================== Basic Tests ====================

#[test]
// Should create BridgingFiPosition
public fun test_create_position() {
  let mut s = test_scenario::begin(OWNER);

  let position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_5_PERCENT,
    s.ctx(),
  );

  assert!(bridgingfi_adapter::vault_id(&position) == OWNER, 0);
  assert!(bridgingfi_adapter::custodian_account(&position) == CUSTODIAN, 1);
  assert!(bridgingfi_adapter::apr_decimal(&position) == APR_5_PERCENT, 2);
  assert!(bridgingfi_adapter::outstanding_balance(&position) == 0, 3);
  assert!(bridgingfi_adapter::last_update_day(&position) == 0, 4);

  transfer::public_transfer(position, OWNER);
  s.end();
}

#[test]
// Should add BridgingFiPosition to vault
public fun test_add_position_to_vault() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();

    let position = bridgingfi_adapter::create_position(
      vault.vault_id(),
      CUSTODIAN,
      APR_5_PERCENT,
      s.ctx(),
    );

    operation::add_new_defi_asset(
      &operation,
      &cap,
      &mut vault,
      0,
      position,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    assert!(vault.contains_asset_type(bridgingfi_asset_type), 0);

    let wrong_asset_type = vault_utils::parse_key<BridgingFiPosition>(1);
    assert!(!vault.contains_asset_type(wrong_asset_type), 1);

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

// ==================== Calculation Tests ====================

#[test]
// Should calculate day index correctly
public fun test_get_day_index() {
  let s = test_scenario::begin(OWNER);

  // Test with Unix epoch timestamp (1970-01-01 00:00:00 UTC)
  let epoch_timestamp: u64 = 0;
  let day_index = bridgingfi_adapter::get_day_index(epoch_timestamp);
  assert!(day_index == 0, 0);

  // Test with one day later (1970-01-02 00:00:00 UTC)
  let one_day_timestamp: u64 = 24 * 3600 * 1000; // 1 day in milliseconds
  let day_index_1 = bridgingfi_adapter::get_day_index(one_day_timestamp);
  assert!(day_index_1 == 1, 1);

  // Test with timestamp in the middle of a day (should round down)
  let mid_day_timestamp: u64 = 12 * 3600 * 1000; // 12 hours in milliseconds
  let day_index_mid = bridgingfi_adapter::get_day_index(mid_day_timestamp);
  assert!(day_index_mid == 0, 2);

  // Test with timestamp just before day boundary (should round down)
  let boundary_timestamp: u64 = 24 * 3600 * 1000 - 1; // 1 ms before day 1
  let day_index_boundary = bridgingfi_adapter::get_day_index(
    boundary_timestamp,
  );
  assert!(day_index_boundary == 0, 3);

  // Test with timestamp at day boundary (should be day 1)
  let boundary_timestamp2: u64 = 24 * 3600 * 1000; // exactly day 1
  let day_index_boundary2 = bridgingfi_adapter::get_day_index(
    boundary_timestamp2,
  );
  assert!(day_index_boundary2 == 1, 4);

  // Test with large timestamp (year 2100, approximately)
  let large_timestamp: u64 = 4102444800000; // 2100-01-01 00:00:00 UTC
  let day_index_large = bridgingfi_adapter::get_day_index(large_timestamp);
  // Should be approximately 47482 days (130 years * 365 + leap years)
  assert!(day_index_large > 47000, 5);
  assert!(day_index_large < 48000, 6);

  s.end();
}

#[test]
// Should calculate pow_d correctly
public fun test_pow_d() {
  let s = test_scenario::begin(OWNER);

  // Test: 1.0 ^ 10 = 1.0
  let one = vault_utils::to_decimals(1);
  let result1 = bridgingfi_adapter::pow_d(one, 10);
  assert!(result1 == one, 0);

  // Test: 2.0 ^ 0 = 1.0
  let two = vault_utils::to_decimals(2);
  let result2 = bridgingfi_adapter::pow_d(two, 0);
  assert!(result2 == one, 1);

  // Test: 2.0 ^ 1 = 2.0
  let result3 = bridgingfi_adapter::pow_d(two, 1);
  assert!(result3 == two, 2);

  // Test: 2.0 ^ 2 = 4.0
  let result4 = bridgingfi_adapter::pow_d(two, 2);
  let four = vault_utils::to_decimals(4);
  assert!(result4 == four, 3);

  // Test: 0.5 ^ 10 (small base)
  let half = vault_utils::to_decimals(5) / 10; // 0.5 in 1e9 format
  let result5 = bridgingfi_adapter::pow_d(half, 10);
  // 0.5^10 = 0.0009765625, should be very small
  assert!(result5 < vault_utils::to_decimals(1), 4);

  // Test: 1.1 ^ 365 (large exponent, simulating 1 year)
  let one_point_one = vault_utils::to_decimals(11) / 10; // 1.1 in 1e9 format
  let result6 = bridgingfi_adapter::pow_d(one_point_one, 365);
  // 1.1^365 should be very large
  assert!(result6 > vault_utils::to_decimals(1000000), 5);

  // Test: 1.0 ^ 365 = 1.0
  let result7 = bridgingfi_adapter::pow_d(one, 365);
  assert!(result7 == one, 6);

  s.end();
}

#[test]
// Should calculate current debt with compound interest
public fun test_get_current_debt() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  // Create position with 5% APR
  let mut position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_5_PERCENT,
    s.ctx(),
  );

  // Set initial outstanding balance to 1 SUI
  bridgingfi_adapter::set_outstanding_balance(
    &mut position,
    INITIAL_INVESTMENT,
  );

  // Set last_update_day to day 0
  bridgingfi_adapter::update_last_update_day(&mut position, 0);

  // Advance clock by 1 day (86400000 ms)
  clock::set_for_testing(&mut clock, 86400000);

  // Calculate current debt (should be approximately 1 SUI * (1 + 0.05/365))
  let current_debt = bridgingfi_adapter::get_current_debt(&position, &clock);

  // Expected: 1_000_000_000 * (1 + 0.05/365) = 1_000_136_986.3...
  // We check if the result is within a small tolerance.
  let expected_debt_approx = 1_000_136_986;
  let diff = if (current_debt > expected_debt_approx) {
    current_debt - expected_debt_approx
  } else {
    expected_debt_approx - current_debt
  };
  assert!(diff <= 1, 0);

  // Test with 0 days (should return snapshot debt)
  bridgingfi_adapter::update_last_update_day(
    &mut position,
    bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock)),
  );
  let current_debt_zero_days = bridgingfi_adapter::get_current_debt(
    &position,
    &clock,
  );
  // With 0 days passed, debt should be equal to the initial investment (snapshot)
  assert!(current_debt_zero_days == (INITIAL_INVESTMENT as u256), 2);

  transfer::public_transfer(position, OWNER);
  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should calculate compound interest correctly over 30 days
public fun test_compound_interest_30_days() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  let mut position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_10_PERCENT, // Use 10% APR for more significant interest
    s.ctx(),
  );

  bridgingfi_adapter::set_outstanding_balance(
    &mut position,
    INITIAL_INVESTMENT,
  );

  // Set last_update_day to day 0
  bridgingfi_adapter::update_last_update_day(&mut position, 0);

  // Advance clock by 30 days
  clock::set_for_testing(&mut clock, 30 * 86400000);

  let current_debt = bridgingfi_adapter::get_current_debt(&position, &clock);

  // Expected for 30 days at 10% APR:
  // rate_per_day = 0.10 / 365 = 0.0002739726
  // base = 1.0002739726
  // compounded_rate = base ^ 30 = 1.008256...
  // debt = 1_000_000_000 * 1.008256... = 1,008,256,xxx
  // Let's calculate it precisely to verify
  let apr_decimal = APR_10_PERCENT;
  let days_per_year_decimal = vault_utils::to_decimals(365);
  let rate_per_day = vault_utils::div_d(apr_decimal, days_per_year_decimal);
  let one_decimal = vault_utils::to_decimals(1);
  let base = one_decimal + rate_per_day;
  let compounded_rate = bridgingfi_adapter::pow_d(base, 30);
  let expected_debt_u256 = vault_utils::mul_d(
    vault_utils::to_decimals(INITIAL_INVESTMENT as u256),
    compounded_rate,
  );
  let expected_debt = vault_utils::from_decimals(expected_debt_u256);

  let diff = if (current_debt > expected_debt) {
    current_debt - expected_debt
  } else {
    expected_debt - current_debt
  };
  assert!(diff <= 1, 1);

  transfer::public_transfer(position, OWNER);
  clock.destroy_for_testing();
  s.end();
}

// ==================== Boundary and Edge Case Tests ====================

#[test]
// Should handle zero debt correctly
public fun test_get_current_debt_zero_balance() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  let mut position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_5_PERCENT,
    s.ctx(),
  );

  // Set outstanding balance to 0
  bridgingfi_adapter::set_outstanding_balance(&mut position, 0);
  bridgingfi_adapter::update_last_update_day(&mut position, 0);

  // Advance clock by 1 day
  clock::set_for_testing(&mut clock, 86400000);

  let current_debt = bridgingfi_adapter::get_current_debt(&position, &clock);
  assert!(current_debt == 0, 0);

  transfer::public_transfer(position, OWNER);
  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle zero APR correctly
public fun test_get_current_debt_zero_apr() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  let mut position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_0_PERCENT, // 0% APR
    s.ctx(),
  );

  bridgingfi_adapter::set_outstanding_balance(
    &mut position,
    INITIAL_INVESTMENT,
  );
  bridgingfi_adapter::update_last_update_day(&mut position, 0);

  // Advance clock by 30 days
  clock::set_for_testing(&mut clock, 30 * 86400000);

  let current_debt = bridgingfi_adapter::get_current_debt(&position, &clock);
  // With 0% APR, debt should remain the same
  assert!(current_debt == (INITIAL_INVESTMENT as u256), 0);

  transfer::public_transfer(position, OWNER);
  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle large number of days correctly
public fun test_get_current_debt_large_days() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  let mut position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_5_PERCENT,
    s.ctx(),
  );

  bridgingfi_adapter::set_outstanding_balance(
    &mut position,
    INITIAL_INVESTMENT,
  );
  bridgingfi_adapter::update_last_update_day(&mut position, 0);

  // Advance clock by 365 days (1 year)
  clock::set_for_testing(&mut clock, 365 * 86400000);

  let current_debt = bridgingfi_adapter::get_current_debt(&position, &clock);

  // Expected: 1 SUI * (1 + 0.05/365)^365 ≈ 1.051271 SUI (daily compounding)
  // With daily compounding, the result should be slightly more than simple interest (1.05)
  let expected_min = 1_050_000_000; // 1.05 SUI (simple interest lower bound)
  let expected_max = 1_052_000_000; // Allow tolerance for compounding (≈1.051271)
  assert!(current_debt >= expected_min, 0);
  assert!(current_debt <= expected_max, 1);

  transfer::public_transfer(position, OWNER);
  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle same day correctly (no compounding)
public fun test_get_current_debt_same_day() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  let mut position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_5_PERCENT,
    s.ctx(),
  );

  bridgingfi_adapter::set_outstanding_balance(
    &mut position,
    INITIAL_INVESTMENT,
  );

  // Set last_update_day to current day
  let current_day = bridgingfi_adapter::get_day_index(
    clock::timestamp_ms(&clock),
  );
  bridgingfi_adapter::update_last_update_day(&mut position, current_day);

  // Calculate debt on the same day (should return snapshot debt, no compounding)
  let current_debt = bridgingfi_adapter::get_current_debt(&position, &clock);
  // With 0 days passed, debt should be equal to the snapshot
  assert!(current_debt == (INITIAL_INVESTMENT as u256), 0);

  transfer::public_transfer(position, OWNER);
  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should create position with zero APR
public fun test_create_position_zero_apr() {
  let mut s = test_scenario::begin(OWNER);

  let position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_0_PERCENT,
    s.ctx(),
  );

  assert!(bridgingfi_adapter::apr_decimal(&position) == APR_0_PERCENT, 0);
  assert!(bridgingfi_adapter::outstanding_balance(&position) == 0, 1);

  transfer::public_transfer(position, OWNER);
  s.end();
}

#[test]
// Should create position with high APR
public fun test_create_position_high_apr() {
  let mut s = test_scenario::begin(OWNER);

  let position = bridgingfi_adapter::create_position(
    OWNER,
    CUSTODIAN,
    APR_100_PERCENT, // 100% APR
    s.ctx(),
  );

  assert!(bridgingfi_adapter::apr_decimal(&position) == APR_100_PERCENT, 0);

  transfer::public_transfer(position, OWNER);
  s.end();
}

#[test]
// Should create position with same vault and custodian address
public fun test_create_position_same_addresses() {
  let mut s = test_scenario::begin(OWNER);

  // Create position where vault_id == custodian_account
  let position = bridgingfi_adapter::create_position(
    OWNER,
    OWNER, // Same as vault_id
    APR_5_PERCENT,
    s.ctx(),
  );

  assert!(bridgingfi_adapter::vault_id(&position) == OWNER, 0);
  assert!(bridgingfi_adapter::custodian_account(&position) == OWNER, 1);

  transfer::public_transfer(position, OWNER);
  s.end();
}
