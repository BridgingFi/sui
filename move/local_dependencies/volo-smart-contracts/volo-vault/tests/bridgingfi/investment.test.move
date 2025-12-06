#[test_only]
module volo_vault::bridgingfi_investment_test;

use std::ascii::String;
use std::type_name;
use sui::clock;
use sui::coin;
use sui::test_scenario;
use volo_vault::bridgingfi_adapter::{Self, BridgingFiPosition};
use volo_vault::bridgingfi_test_helpers;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::vault::{Self, Vault, OperatorCap, Operation, AdminCap};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

const OWNER: address = @0xa;
const CUSTODIAN: address = @0xb;
const USER: address = @0xc;
const APR_5_PERCENT: u256 = 50_000_000; // 5% in 1e9 format (0.05 * 1e9)
const INITIAL_INVESTMENT: u64 = 1_000_000_000; // 1 SUI
const ADDITIONAL_INVESTMENT: u64 = 500_000_000; // 0.5 SUI
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

#[test]
// Should invest to custodian with address verification
public fun test_invest_to_custodian() {
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
  s.next_tx(OWNER);
  {
    let mut oracle_config = s.take_shared<OracleConfig>();
    test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
    let prices = vector[
      2 * ORACLE_DECIMALS,
      1 * ORACLE_DECIMALS,
      100_000 * ORACLE_DECIMALS,
    ];
    test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
    test_scenario::return_shared(oracle_config);
  };

  // Update initial BridgingFiPosition value (outstanding_balance = 0, so USD value = 0)
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

  // Deposit some funds to vault
  s.next_tx(USER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT * 2,
      s.ctx(),
    );
    vault.return_free_principal(coin.into_balance());
    vault.update_free_principal_value(&config, &clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Update BridgingFiPosition value again after deposit (to ensure initial value is correct)
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

  // Start operation and invest
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();

    let defi_asset_ids = vector[0u8];
    let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];

    let (
      mut asset_bag,
      tx_bag,
      tx_bag_for_check_value_update,
      mut principal_balance,
      coin_type_asset_balance,
    ) = operation::start_op_with_bag<
      SUI_TEST_COIN,
      SUI_TEST_COIN,
      SUI_TEST_COIN,
    >(
      &mut vault,
      &operation,
      &cap,
      &clock,
      defi_asset_ids,
      defi_asset_types,
      INITIAL_INVESTMENT,
      0,
      s.ctx(),
    );

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = asset_bag.remove<String, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // Invest to custodian (with correct address)
    bridgingfi_adapter::invest_to_custodian(
      &mut vault,
      &mut position,
      &mut principal_balance,
      INITIAL_INVESTMENT,
      CUSTODIAN,
      &clock,
      s.ctx(),
    );

    asset_bag.add(bridgingfi_asset_type, position);

    // Step 2: Return assets to vault
    operation::end_op_with_bag<SUI_TEST_COIN, SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      asset_bag,
      tx_bag,
      principal_balance,
      coin_type_asset_balance,
    );

    // Update value after returning assets
    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    vault.update_free_principal_value(&config, &clock);

    // Step 3: Check value update
    operation::end_op_value_update_with_bag<SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      &clock,
      tx_bag_for_check_value_update,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    test_scenario::return_shared(config);
    s.return_to_sender(cap);
  };

  // Verify position was updated
  s.next_tx(OWNER);
  {
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    assert!(
      bridgingfi_adapter::outstanding_balance(position) == INITIAL_INVESTMENT,
      0,
    );
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
    abort_code = bridgingfi_adapter::ERR_CUSTODIAN_ACCOUNT_MISMATCH,
  ),
]
// Should fail if custodian account mismatch
public fun test_invest_to_custodian_wrong_address() {
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
  s.next_tx(OWNER);
  {
    let mut oracle_config = s.take_shared<OracleConfig>();
    test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
    let prices = vector[
      2 * ORACLE_DECIMALS,
      1 * ORACLE_DECIMALS,
      100_000 * ORACLE_DECIMALS,
    ];
    test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
    test_scenario::return_shared(oracle_config);
  };

  // Deposit funds
  s.next_tx(USER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT,
      s.ctx(),
    );
    vault.return_free_principal(coin.into_balance());
    test_scenario::return_shared(vault);
  };

  // Try to invest with wrong address (should fail)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();

    let defi_asset_ids = vector[0u8];
    let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];

    let (
      mut asset_bag,
      tx_bag,
      tx_bag_for_check_value_update,
      mut principal_balance,
      coin_type_asset_balance,
    ) = operation::start_op_with_bag<
      SUI_TEST_COIN,
      SUI_TEST_COIN,
      SUI_TEST_COIN,
    >(
      &mut vault,
      &operation,
      &cap,
      &clock,
      defi_asset_ids,
      defi_asset_types,
      INITIAL_INVESTMENT,
      0,
      s.ctx(),
    );

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = asset_bag.remove<String, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // Try with wrong address (should fail)
    bridgingfi_adapter::invest_to_custodian(
      &mut vault,
      &mut position,
      &mut principal_balance,
      INITIAL_INVESTMENT,
      USER, // Wrong address
      &clock,
      s.ctx(),
    );

    // This code should never execute due to expected failure
    asset_bag.add(bridgingfi_asset_type, position);
    operation::end_op_with_bag<SUI_TEST_COIN, SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      asset_bag,
      tx_bag,
      principal_balance,
      coin_type_asset_balance,
    );
    operation::end_op_value_update_with_bag<SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      &clock,
      tx_bag_for_check_value_update,
    );
    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
// Should handle multiple investments with compound interest
public fun test_multiple_investments_compound_interest() {
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
  s.next_tx(OWNER);
  {
    let mut oracle_config = s.take_shared<OracleConfig>();
    test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
    let prices = vector[
      2 * ORACLE_DECIMALS,
      1 * ORACLE_DECIMALS,
      100_000 * ORACLE_DECIMALS,
    ];
    test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
    test_scenario::return_shared(oracle_config);
  };

  // Update initial BridgingFiPosition value (outstanding_balance = 0, so USD value = 0)
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

  // Deposit funds for both investments
  s.next_tx(USER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT + ADDITIONAL_INVESTMENT,
      s.ctx(),
    );
    vault.return_free_principal(coin.into_balance());
    vault.update_free_principal_value(&config, &clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Update BridgingFiPosition value again after deposit
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

  // First investment
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();

    let defi_asset_ids = vector[0u8];
    let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];

    let (
      mut asset_bag,
      tx_bag,
      tx_bag_for_check_value_update,
      mut principal_balance,
      coin_type_asset_balance,
    ) = operation::start_op_with_bag<
      SUI_TEST_COIN,
      SUI_TEST_COIN,
      SUI_TEST_COIN,
    >(
      &mut vault,
      &operation,
      &cap,
      &clock,
      defi_asset_ids,
      defi_asset_types,
      INITIAL_INVESTMENT,
      0,
      s.ctx(),
    );

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = asset_bag.remove<String, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // First investment
    bridgingfi_adapter::invest_to_custodian(
      &mut vault,
      &mut position,
      &mut principal_balance,
      INITIAL_INVESTMENT,
      CUSTODIAN,
      &clock,
      s.ctx(),
    );

    asset_bag.add(bridgingfi_asset_type, position);

    operation::end_op_with_bag<SUI_TEST_COIN, SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      asset_bag,
      tx_bag,
      principal_balance,
      coin_type_asset_balance,
    );

    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    vault.update_free_principal_value(&config, &clock);

    operation::end_op_value_update_with_bag<SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      &clock,
      tx_bag_for_check_value_update,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    test_scenario::return_shared(config);
    s.return_to_sender(cap);
  };

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

  // Update value after 30 days (to calculate compound interest)
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

  // Second investment (should add to the compounded debt)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();
    let config = s.take_shared<OracleConfig>();

    let defi_asset_ids = vector[0u8];
    let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];

    let (
      mut asset_bag,
      tx_bag,
      tx_bag_for_check_value_update,
      mut principal_balance,
      coin_type_asset_balance,
    ) = operation::start_op_with_bag<
      SUI_TEST_COIN,
      SUI_TEST_COIN,
      SUI_TEST_COIN,
    >(
      &mut vault,
      &operation,
      &cap,
      &clock,
      defi_asset_ids,
      defi_asset_types,
      ADDITIONAL_INVESTMENT,
      0,
      s.ctx(),
    );

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = asset_bag.remove<String, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // Second investment (current debt should include compound interest from first investment)
    bridgingfi_adapter::invest_to_custodian(
      &mut vault,
      &mut position,
      &mut principal_balance,
      ADDITIONAL_INVESTMENT,
      CUSTODIAN,
      &clock,
      s.ctx(),
    );

    asset_bag.add(bridgingfi_asset_type, position);

    operation::end_op_with_bag<SUI_TEST_COIN, SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      asset_bag,
      tx_bag,
      principal_balance,
      coin_type_asset_balance,
    );

    bridgingfi_adapter::update_value(
      &mut vault,
      &config,
      &clock,
      bridgingfi_asset_type,
    );

    vault.update_free_principal_value(&config, &clock);

    operation::end_op_value_update_with_bag<SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      &clock,
      tx_bag_for_check_value_update,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    test_scenario::return_shared(config);
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

    // outstanding_balance should be current_debt_before + ADDITIONAL_INVESTMENT
    // current_debt_before should be approximately INITIAL_INVESTMENT * (1 + 0.05/365) ^ 30
    // For 5% APR over 30 days: rate ≈ 1.0041, so debt ≈ 1,004,100,000
    // After adding 0.5 SUI: outstanding_balance ≈ 1,504,100,000
    let outstanding_balance = bridgingfi_adapter::outstanding_balance(position);
    // Allow some tolerance for compound interest calculation
    assert!(outstanding_balance >= INITIAL_INVESTMENT + ADDITIONAL_INVESTMENT, 0);
    assert!(
      outstanding_balance <= INITIAL_INVESTMENT + ADDITIONAL_INVESTMENT + 5_000_000, // Allow ~0.5% tolerance
      1,
    );

    assert!(
      bridgingfi_adapter::last_update_day(position) == bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock)),
      2,
    );

    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
#[
  expected_failure(
    abort_code = bridgingfi_adapter::ERR_INSUFFICIENT_BALANCE,
  ),
]
// Should fail if insufficient balance
public fun test_invest_to_custodian_insufficient_balance() {
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
  s.next_tx(OWNER);
  {
    let mut oracle_config = s.take_shared<OracleConfig>();
    test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
    let prices = vector[
      2 * ORACLE_DECIMALS,
      1 * ORACLE_DECIMALS,
      100_000 * ORACLE_DECIMALS,
    ];
    test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
    test_scenario::return_shared(oracle_config);
  };

  // Deposit funds (less than investment amount)
  s.next_tx(USER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT / 2, // Only half of required amount
      s.ctx(),
    );
    vault.return_free_principal(coin.into_balance());
    vault.update_free_principal_value(&config, &clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Try to invest with insufficient balance (should fail)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();

    let defi_asset_ids = vector[0u8];
    let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];

    // Start with available amount
    let (
      mut asset_bag,
      tx_bag,
      tx_bag_for_check_value_update,
      mut principal_balance,
      coin_type_asset_balance,
    ) = operation::start_op_with_bag<
      SUI_TEST_COIN,
      SUI_TEST_COIN,
      SUI_TEST_COIN,
    >(
      &mut vault,
      &operation,
      &cap,
      &clock,
      defi_asset_ids,
      defi_asset_types,
      INITIAL_INVESTMENT / 2, // Only borrow available amount
      0,
      s.ctx(),
    );

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = asset_bag.remove<String, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // Try to invest with insufficient balance (should fail)
    bridgingfi_adapter::invest_to_custodian(
      &mut vault,
      &mut position,
      &mut principal_balance,
      INITIAL_INVESTMENT, // More than available in principal_balance
      CUSTODIAN,
      &clock,
      s.ctx(),
    );

    // This code should never execute due to expected failure
    asset_bag.add(bridgingfi_asset_type, position);
    operation::end_op_with_bag<SUI_TEST_COIN, SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      asset_bag,
      tx_bag,
      principal_balance,
      coin_type_asset_balance,
    );
    operation::end_op_value_update_with_bag<SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      &clock,
      tx_bag_for_check_value_update,
    );
    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
#[
  expected_failure(
    abort_code = vault::ERR_OPERATOR_FREEZED,
    location = vault,
  ),
]
// Should fail if operator is freezed
public fun test_invest_to_custodian_operator_freezed() {
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

  // Freeze operator
  s.next_tx(OWNER);
  {
    let admin_cap = s.take_from_sender<AdminCap>();
    let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let mut operation = s.take_shared<Operation>();
    let operator_cap = s.take_from_sender<OperatorCap>();

    vault_manage::set_operator_freezed(
      &admin_cap,
      &mut operation,
      operator_cap.operator_id(),
      true,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(admin_cap);
    s.return_to_sender(operator_cap);
  };

  // Set mock aggregator and price
  s.next_tx(OWNER);
  {
    let mut oracle_config = s.take_shared<OracleConfig>();
    test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
    let prices = vector[
      2 * ORACLE_DECIMALS,
      1 * ORACLE_DECIMALS,
      100_000 * ORACLE_DECIMALS,
    ];
    test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
    test_scenario::return_shared(oracle_config);
  };

  // Deposit funds
  s.next_tx(USER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let config = s.take_shared<OracleConfig>();
    let coin = coin::mint_for_testing<SUI_TEST_COIN>(
      INITIAL_INVESTMENT,
      s.ctx(),
    );
    vault.return_free_principal(coin.into_balance());
    vault.update_free_principal_value(&config, &clock);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(config);
  };

  // Try to invest with freezed operator (should fail)
  s.next_tx(OWNER);
  {
    let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();

    let defi_asset_ids = vector[0u8];
    let defi_asset_types = vector[std::type_name::get<BridgingFiPosition>()];

    let (
      mut asset_bag,
      tx_bag,
      tx_bag_for_check_value_update,
      mut principal_balance,
      coin_type_asset_balance,
    ) = operation::start_op_with_bag<
      SUI_TEST_COIN,
      SUI_TEST_COIN,
      SUI_TEST_COIN,
    >(
      &mut vault,
      &operation,
      &cap,
      &clock,
      defi_asset_ids,
      defi_asset_types,
      INITIAL_INVESTMENT,
      0,
      s.ctx(),
    );

    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = asset_bag.remove<String, BridgingFiPosition>(
      bridgingfi_asset_type,
    );

    // Try to invest with freezed operator (should fail)
    bridgingfi_adapter::invest_to_custodian(
      &mut vault,
      &mut position,
      &mut principal_balance,
      INITIAL_INVESTMENT,
      CUSTODIAN,
      &clock,
      s.ctx(),
    );

    // This code should never execute due to expected failure
    asset_bag.add(bridgingfi_asset_type, position);
    operation::end_op_with_bag<SUI_TEST_COIN, SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      asset_bag,
      tx_bag,
      principal_balance,
      coin_type_asset_balance,
    );
    operation::end_op_value_update_with_bag<SUI_TEST_COIN, SUI_TEST_COIN>(
      &mut vault,
      &operation,
      &cap,
      &clock,
      tx_bag_for_check_value_update,
    );
    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };

  clock.destroy_for_testing();
  s.end();
}
