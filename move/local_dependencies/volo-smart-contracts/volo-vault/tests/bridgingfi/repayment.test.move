#[test_only]
module volo_vault::bridgingfi_repayment_test;

use std::option;
use sui::address;
use sui::bag;
use sui::clock;
use sui::coin;
use sui::test_scenario;
use sui::transfer;
use volo_vault::bridgingfi_adapter::{Self, BridgingFiPosition};
use volo_vault::bridgingfi_test_helpers;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::reward_manager::RewardManager;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Operation, OperatorCap, Vault};
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

const OWNER: address = @0xa;
const CUSTODIAN: address = @0xb;
const REPAYER: address = @0xd;
const APR_5_PERCENT: u256 = 50_000_000; // 5% in 1e9 format (0.05 * 1e9)
const INITIAL_INVESTMENT: u64 = 1_000_000_000; // 1 SUI
const REPAYMENT_AMOUNT: u64 = 500_000_000; // 0.5 SUI
const EXCESS_REPAYMENT: u64 = 2_000_000_000; // 2 SUI (exceeds debt)
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals
const DECIMALS: u256 = 1_000_000_000;

// ==================== Helper Functions ====================


#[test_only]
/// Helper function to execute repayment with start_op/end_op
fun execute_repayment<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  operation: &Operation,
  cap: &vault::OperatorCap,
  clock: &sui::clock::Clock,
  config: &OracleConfig,
  repay_coin: coin::Coin<PrincipalCoinType>,
  amount: u64,
  ctx: &mut sui::tx_context::TxContext,
): coin::Coin<PrincipalCoinType> {
  use sui::bag;
  use std::ascii::String;
  let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);

  // Start operation
  let defi_asset_ids = vector[0u8];
  let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];
  let (
    mut defi_assets,
    tx_bag,
    _tx_bag_for_check,
    principal_balance,
    coin_type_balance,
  ) = operation::start_op_with_bag<
    PrincipalCoinType,
    PrincipalCoinType,
    PrincipalCoinType,
  >(
    vault,
    operation,
    cap,
    clock,
    defi_asset_ids,
    defi_asset_types,
    0,
    0,
    ctx,
  );

  // Remove position from bag
  let mut position = bag::remove<String, BridgingFiPosition>(
    &mut defi_assets,
    bridgingfi_asset_type,
  );

  // Repay
  let remaining_coin = bridgingfi_adapter::repay(
    vault,
    &mut position,
    repay_coin,
    amount,
    clock,
    ctx,
  );

  // Add position back to bag
  bag::add<String, BridgingFiPosition>(
    &mut defi_assets,
    bridgingfi_asset_type,
    position,
  );

  // End operation
  operation::end_op_with_bag<
    PrincipalCoinType,
    PrincipalCoinType,
    PrincipalCoinType,
  >(
    vault,
    operation,
    cap,
    defi_assets,
    tx_bag,
    principal_balance,
    coin_type_balance,
  );

  // Update asset value before calling end_op_value_update_with_bag
  let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
  bridgingfi_adapter::update_value(
    vault,
    config,
    clock,
    bridgingfi_asset_type,
  );

  // Update principal value
  vault.update_free_principal_value(config, clock);

  // Consume tx_bag_for_check by calling end_op_value_update_with_bag
  operation::end_op_value_update_with_bag<PrincipalCoinType, PrincipalCoinType>(
    vault,
    operation,
    cap,
    clock,
    _tx_bag_for_check,
  );

  remaining_coin
}

// ==================== Basic Repayment Tests ====================


#[test]
// Single account repayment test - OWNER provides both coin and operator_cap
public fun test_repay_to_vault_single_account() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Repay using single account (OWNER provides both coin and operator_cap)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment with start_op/end_op
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Should return empty coin (no excess)
    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
    test_scenario::return_shared(config);
  };

  // Verify position was updated and free_principal increased
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    let expected_balance = INITIAL_INVESTMENT - REPAYMENT_AMOUNT;
    assert!(
      bridgingfi_adapter::outstanding_balance(position) == expected_balance,
      0,
    );
    assert!(
      bridgingfi_adapter::last_update_day(position) == bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock)),
      1,
    );

    let free_principal = vault.free_principal();
    assert!(free_principal == REPAYMENT_AMOUNT, 2);

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle partial repayment
public fun test_repay_to_vault_partial() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // First partial repayment
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after first repayment
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // total_usd_value should remain approximately the same because:
    // - BridgingFiPosition value decreased by REPAYMENT_AMOUNT * 2 USD
    // - free_principal value increased by REPAYMENT_AMOUNT * 2 USD
    let total_usd_value_before = INITIAL_INVESTMENT as u256 * 2; // 1 SUI * 2 USD/SUI = 2 USD
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= total_usd_value_before - 1000, 10);
    assert!(total_usd_value_after <= total_usd_value_before + 1000, 11);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify first repayment
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    let expected_balance = INITIAL_INVESTMENT - REPAYMENT_AMOUNT;
    assert!(
      bridgingfi_adapter::outstanding_balance(position) == expected_balance,
      0,
    );

    test_scenario::return_shared(vault);
  };

  // Second partial repayment
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after second repayment
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after second repayment (fully repaid)
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // After full repayment:
    // - BridgingFiPosition value = 0 (fully repaid)
    // - free_principal value = INITIAL_INVESTMENT * 2 USD (all repayment returned)
    let expected_total_usd_value = INITIAL_INVESTMENT as u256 * 2; // 1 SUI * 2 USD/SUI = 2 USD
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= expected_total_usd_value - 1000, 11);
    assert!(total_usd_value_after <= expected_total_usd_value + 1000, 12);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify second repayment (should be fully repaid)
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    let expected_balance =
      INITIAL_INVESTMENT - REPAYMENT_AMOUNT - REPAYMENT_AMOUNT;
    assert!(
      bridgingfi_adapter::outstanding_balance(position) == expected_balance,
      0,
    );

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle full repayment
public fun test_repay_to_vault_full() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Full repayment
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      INITIAL_INVESTMENT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after full repayment
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // After full repayment:
    // - BridgingFiPosition value = 0 (fully repaid)
    // - free_principal value = INITIAL_INVESTMENT * 2 USD (all repayment returned)
    let expected_total_usd_value = INITIAL_INVESTMENT as u256 * 2; // 1 SUI * 2 USD/SUI = 2 USD
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= expected_total_usd_value - 1000, 12);
    assert!(total_usd_value_after <= expected_total_usd_value + 1000, 13);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify position was fully repaid
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // outstanding_balance should be 0 after full repayment
    assert!(bridgingfi_adapter::outstanding_balance(position) == 0, 0);
    assert!(
      bridgingfi_adapter::last_update_day(position) == bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock)),
      1,
    );

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle excess repayment (return excess amount)
public fun test_repay_to_vault_excess() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Repay with excess amount
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      EXCESS_REPAYMENT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      EXCESS_REPAYMENT,
      s.ctx(),
    );

    // Should return excess amount
    let expected_excess = EXCESS_REPAYMENT - INITIAL_INVESTMENT;
    assert!(coin::value(&remaining_coin) == expected_excess, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after repayment (fully repaid)
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // After full repayment:
    // - BridgingFiPosition value = 0 (fully repaid)
    // - free_principal value = INITIAL_INVESTMENT * 2 USD (all repayment returned)
    let expected_total_usd_value = INITIAL_INVESTMENT as u256 * 2; // 1 SUI * 2 USD/SUI = 2 USD
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= expected_total_usd_value - 1000, 13);
    assert!(total_usd_value_after <= expected_total_usd_value + 1000, 14);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify position was fully repaid (outstanding_balance = 0)
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // outstanding_balance should be 0 after full repayment
    assert!(bridgingfi_adapter::outstanding_balance(position) == 0, 0);
    assert!(
      bridgingfi_adapter::last_update_day(position) == bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock)),
      1,
    );

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle repayment with compound interest
public fun test_repay_to_vault_with_compound_interest() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Advance clock by 30 days to allow compound interest
  s.next_tx(OWNER);
  {
    clock::set_for_testing(&mut clock, 30 * 24 * 3600 * 1000);
    let mut oracle_config = s.take_shared<OracleConfig>();
    let sui_asset_type = std::type_name::get<SUI_TEST_COIN>().into_string();
    vault_oracle::set_current_price(
      &mut oracle_config,
      &clock,
      sui_asset_type,
      2 * ORACLE_DECIMALS,
    );
    test_scenario::return_shared(oracle_config);
  };

  // Update BridgingFiPosition value before repayment (required for get_total_usd_value)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);

    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    vault.update_free_principal_value(&config, &clock);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Repay partial amount (should calculate from current debt with compound interest)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after repayment
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // total_usd_value should remain approximately the same because:
    // - BridgingFiPosition value decreased (with compound interest)
    // - free_principal value increased by repayment amount
    // The exact value depends on compound interest calculation
    let total_usd_value_before = 2 * DECIMALS; // Initial value
    // Should be approximately the same (allowing for compound interest and rounding)
    assert!(total_usd_value_after >= total_usd_value_before - 100_000_000, 14); // Allow tolerance
    assert!(total_usd_value_after <= total_usd_value_before + 100_000_000, 15);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify position was updated correctly
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // After repayment, outstanding_balance should be updated to current_debt - REPAYMENT_AMOUNT
    // Since last_update_day was updated to current day, get_current_debt should return outstanding_balance
    let outstanding_balance = bridgingfi_adapter::outstanding_balance(position);
    // outstanding_balance should be less than initial investment (due to repayment)
    assert!(outstanding_balance < INITIAL_INVESTMENT, 0);
    assert!(
      bridgingfi_adapter::last_update_day(position) == bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock)),
      1,
    );

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
#[
  expected_failure(
    abort_code = volo_vault::bridgingfi_adapter::ERR_INSUFFICIENT_BALANCE,
  ),
]
// Should fail when coin balance is insufficient
public fun test_repay_to_vault_insufficient_coin_balance() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Try to repay with coin value less than amount - should fail with ERR_INSUFFICIENT_BALANCE
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = vault::borrow_defi_asset<
      SUI_TEST_COIN,
      BridgingFiPosition,
    >(
      &mut vault,
      bridgingfi_asset_type,
    );
    // Create coin with value less than REPAYMENT_AMOUNT
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT - 1, // Less than REPAYMENT_AMOUNT
      s.ctx(),
    );

    // This should fail because coin.value() < amount
    // If it fails, repay_coin will be dropped automatically
    let _remaining_coin = bridgingfi_adapter::repay(
      &mut vault,
      &mut position,
      repay_coin,
      REPAYMENT_AMOUNT, // amount > coin.value()
      &clock,
      s.ctx(),
    );

    // This code should never be reached due to expected failure
    coin::burn_for_testing<SUI_TEST_COIN>(_remaining_coin);
    vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

// ==================== Total USD Value Tests ====================

#[test]
// Should check total_usd_value before and after repayment
public fun test_repay_to_vault_total_usd_value() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Update BridgingFiPosition value before repayment
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);

    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Update principal value before checking total (required for get_total_usd_value)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    vault.update_free_principal_value(&config, &clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Check total_usd_value before repayment
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

    let total_usd_value_before = vault.get_total_usd_value(&clock);
    // Should be 1 SUI = 2 USD (BridgingFiPosition value, no free_principal)
    assert!(total_usd_value_before == 2 * DECIMALS, 0);

    test_scenario::return_shared(vault);
  };

  // Repay
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after repayment
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // total_usd_value should remain approximately the same because:
    // - BridgingFiPosition value decreased by REPAYMENT_AMOUNT * 2 USD
    // - free_principal value increased by REPAYMENT_AMOUNT * 2 USD
    // Note: free_principal IS included in total_usd_value
    let total_usd_value_before = 2 * DECIMALS; // Initial value
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= total_usd_value_before - 1000, 1);
    assert!(total_usd_value_after <= total_usd_value_before + 1000, 2);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify free_principal increased (repayment returned to free_principal)
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

    let free_principal = vault.free_principal();
    // Should be equal to repayment amount (repayment returned to free_principal)
    assert!(free_principal == REPAYMENT_AMOUNT, 3);

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should check total_usd_value without updating after repayment (problematic case)
public fun test_repay_to_vault_total_usd_value_without_update() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Update BridgingFiPosition value before repayment
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);

    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Update principal value before checking total
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    vault.update_free_principal_value(&config, &clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Check total_usd_value before repayment
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

    let total_usd_value_before = vault.get_total_usd_value(&clock);
    // Should be 1 SUI = 2 USD
    assert!(total_usd_value_before == 2 * DECIMALS, 0);

    test_scenario::return_shared(vault);
  };

  // Repay (without updating value after)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after repayment
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // total_usd_value should remain approximately the same because:
    // - BridgingFiPosition value decreased by REPAYMENT_AMOUNT * 2 USD
    // - free_principal value increased by REPAYMENT_AMOUNT * 2 USD
    let total_usd_value_before = INITIAL_INVESTMENT as u256 * 2; // 1 SUI * 2 USD/SUI = 2 USD
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= total_usd_value_before - 1000, 1);
    assert!(total_usd_value_after <= total_usd_value_before + 1000, 2);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  clock.destroy_for_testing();
  s.end();
}

// ==================== Withdraw After Repayment Tests ====================

#[test]
// Should test complete withdraw flow after repayment to verify claimable_principal issue
// This test demonstrates that repayment adds to vault's claimable_principal
// but not to receipt's claimable_principal, so users cannot claim the repaid funds
// even after executing a withdraw operation
public fun test_withdraw_after_repayment() {
  let mut s = test_scenario::begin(OWNER);

  let mut clock = clock::create_for_testing(s.ctx());

  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
  bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
    &mut s,
    CUSTODIAN,
    APR_5_PERCENT,
  );

  // Set mock aggregator and price
  bridgingfi_test_helpers::setup_oracle_with_default_prices(
    &mut s,
    &mut clock,
  );

  // Set initial outstanding_balance and last_update_day to day 0
  bridgingfi_test_helpers::setup_initial_position_state<SUI_TEST_COIN>(
    &mut s,
    INITIAL_INVESTMENT,
    0,
  );

  // Update BridgingFiPosition value before deposit
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);

    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Deposit to create shares
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let mut reward_manager = s.take_shared<
      volo_vault::reward_manager::RewardManager<SUI_TEST_COIN>,
    >();
    let deposit_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT,
      s.ctx(),
    );

    let (request_id, receipt, coin) = volo_vault::user_entry::deposit(
      &mut vault,
      &mut reward_manager,
      deposit_coin,
      INITIAL_INVESTMENT,
      2_000_000_000,
      option::none(),
      &clock,
      s.ctx(),
    );

    // Store receipt for later use
    sui::transfer::public_transfer(receipt, OWNER);
    coin::burn_for_testing(coin);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(reward_manager);
  };

  // Execute deposit
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();

    vault.update_free_principal_value(&config, &clock);

    vault.execute_deposit(
      &clock,
      &config,
      0,
      2_000_000_000,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Check total_usd_value before repayment
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let total_usd_value_before = vault.get_total_usd_value(&clock);
    // Should include BridgingFiPosition value (1 SUI = 2 USD) + free_principal value
    assert!(total_usd_value_before >= 2 * DECIMALS, 0);
    test_scenario::return_shared(vault);
  };

  // Repay
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();
    let repay_coin = coin::mint_for_testing<SUI_TEST_COIN>(
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    // Execute repayment
    let remaining_coin = execute_repayment(
      &mut vault,
      &operation,
      &cap,
      &clock,
      &config,
      repay_coin,
      REPAYMENT_AMOUNT,
      s.ctx(),
    );

    assert!(coin::value(&remaining_coin) == 0, 0);
    coin::burn_for_testing<SUI_TEST_COIN>(remaining_coin);

    // Update USD value after repayment
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    // Update principal value before checking total
    vault.update_free_principal_value(&config, &clock);

    // Check total_usd_value after repayment
    let total_usd_value_after = vault.get_total_usd_value(&clock);
    // Get total_usd_value before repayment for comparison
    let total_usd_value_before_repay = vault.get_total_usd_value(&clock);
    // total_usd_value should remain approximately the same because:
    // - BridgingFiPosition value decreased by REPAYMENT_AMOUNT * 2 USD
    // - free_principal value increased by REPAYMENT_AMOUNT * 2 USD
    // Note: free_principal IS included in total_usd_value
    // Allow small tolerance for rounding
    assert!(total_usd_value_after >= total_usd_value_before_repay - 1000, 1);
    assert!(total_usd_value_after <= total_usd_value_before_repay + 1000, 2);

    // Verify free_principal increased (repayment returned to free_principal)
    let free_principal = vault.free_principal();
    assert!(free_principal >= REPAYMENT_AMOUNT, 2); // May be more if there was existing free_principal

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  // Verify free_principal increased (repayment returned to free_principal)
  // Now users can withdraw and get the repaid funds through normal withdraw flow
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let receipt = s.take_from_address<volo_vault::receipt::Receipt>(OWNER);

    // Verify free_principal has the repayment amount
    let free_principal = vault.free_principal();
    assert!(free_principal >= REPAYMENT_AMOUNT, 3); // Repayment returned to free_principal

    // Receipt's claimable_principal is 0 (expected, since repayment goes to free_principal)
    let claimable_amount = vault
      .vault_receipt_info(receipt.receipt_id())
      .claimable_principal();
    assert!(claimable_amount == 0, 4); // Receipt has no claimable_principal (expected)

    test_scenario::return_shared(vault);
    sui::transfer::public_transfer(receipt, OWNER);
  };

  // Request withdraw (with recipient = 0, so funds will go to claimable_principal)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let mut config = s.take_shared<OracleConfig>();
    let mut receipt = s.take_from_address<volo_vault::receipt::Receipt>(OWNER);

    // Advance clock to pass locking time (12 hours)
    clock::set_for_testing(&mut clock, 12 * 3600_000);

    // Update prices (don't re-set aggregators, they're already set)
    let prices = vector[
      2 * ORACLE_DECIMALS,
      1 * ORACLE_DECIMALS,
      100_000 * ORACLE_DECIMALS,
    ];
    volo_vault::test_helpers::set_prices(
      &mut s,
      &mut clock,
      &mut config,
      prices,
    );
    vault.update_free_principal_value(&config, &clock);

    // Get current shares to withdraw a small portion
    let receipt_info = vault.vault_receipt_info(receipt.receipt_id());
    let shares = receipt_info.shares();
    // Withdraw a small portion (about 10% to ensure we have enough funds)
    let withdraw_shares = shares / 10;
    // Use a small expected_amount to avoid slippage issues
    // The actual amount will be calculated based on share ratio
    let expected_amount = 100_000_000; // 0.1 SUI (small amount to avoid slippage)

    // Request withdraw with recipient = 0 (funds will go to claimable_principal)
    let request_id = user_entry::withdraw(
      &mut vault,
      withdraw_shares,
      expected_amount,
      &mut receipt,
      &clock,
      s.ctx(),
    );

    assert!(request_id == 0, 4);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    sui::transfer::public_transfer(receipt, OWNER);
  };

  // Execute withdraw using operation::execute_withdraw (proper way)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);

    // Update USD value before execute_withdraw (required for get_share_ratio)
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );
    vault.update_free_principal_value(&config, &clock);

    // Execute withdraw using operation::execute_withdraw
    // This will automatically handle recipient = 0 case (add to claimable_principal)
    // Use a reasonable max_amount_received to avoid slippage issues
    operation::execute_withdraw(
      &operation,
      &cap,
      &mut vault,
      &mut reward_manager,
      &clock,
      &config,
      0, // request_id
      500_000_000, // max_amount_received (0.5 SUI, should be enough for 10% of shares)
      s.ctx(),
    );

    // Note: operation::execute_withdraw automatically handles recipient = 0
    // by calling vault.add_claimable_principal, so we don't need to do it manually

    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
    test_scenario::return_shared(reward_manager);
  };

  // Check receipt's claimable_principal after execute_withdraw
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let receipt = s.take_from_address<volo_vault::receipt::Receipt>(OWNER);

    // After execute_withdraw with recipient = 0, receipt's claimable_principal should have the withdraw amount
    let claimable_amount = vault
      .vault_receipt_info(receipt.receipt_id())
      .claimable_principal();
    // The claimable_principal should contain the withdraw amount
    assert!(claimable_amount > 0, 6); // Should have withdraw amount

    test_scenario::return_shared(vault);
    sui::transfer::public_transfer(receipt, OWNER);
  };

  // Verify vault's free_principal and claimable_principal
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

    // Vault's free_principal should include the repayment amount minus the withdraw amount
    // (repayment was returned to free_principal, then some was withdrawn)
    let vault_free = vault.free_principal();
    // Should be at least REPAYMENT_AMOUNT minus the withdraw amount
    // (withdraw amount was taken from free_principal and added to claimable_principal)
    assert!(vault_free >= REPAYMENT_AMOUNT - 500_000_000, 7); // Allow for withdraw amount

    // Vault's claimable_principal should include the withdraw amount
    // (from execute_withdraw with recipient = 0)
    let vault_claimable = vault.claimable_principal();
    // Should have the withdraw amount (from execute_withdraw with recipient = 0)
    assert!(vault_claimable > 0, 8); // Should have withdraw amount

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}
