#[test_only]
module volo_vault::bridgingfi_value_update_test;

use sui::clock;
use sui::test_scenario;
use volo_vault::bridgingfi_adapter::{Self, BridgingFiPosition};
use volo_vault::bridgingfi_test_helpers;
use volo_vault::init_vault;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use std::type_name;
use volo_vault::vault::{Self, Vault};
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

const OWNER: address = @0xa;
const CUSTODIAN: address = @0xb;
const APR_5_PERCENT: u256 = 50_000_000; // 5% in 1e9 format (0.05 * 1e9)
const APR_10_PERCENT: u256 = 100_000_000; // 10% in 1e9 format (0.10 * 1e9)
const APR_0_PERCENT: u256 = 0; // 0% APR
const INITIAL_INVESTMENT: u64 = 1_000_000_000; // 1 SUI
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals
const DECIMALS: u256 = 1_000_000_000;

// ==================== Basic Value Update Tests ====================

#[test]
// Should update BridgingFiPosition value with zero balance
public fun test_update_bridgingfi_position_value_zero_balance() {
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

    // Update value (outstanding_balance = 0, so USD value should be 0)
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

    // Check total usd value
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 0, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// Should update BridgingFiPosition value with debt
public fun test_update_bridgingfi_position_value_with_debt() {
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

    // Set initial outstanding_balance manually (simulating after investment)
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let mut position = vault::borrow_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            &mut vault,
            bridgingfi_asset_type,
        );

        // Set outstanding_balance to 1 SUI
        bridgingfi_adapter::set_outstanding_balance(&mut position, INITIAL_INVESTMENT);
        // Set last_update_day to current day
        let current_day = bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock));
        bridgingfi_adapter::update_last_update_day(&mut position, current_day);

        vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
        test_scenario::return_shared(vault);
    };

    // Update value (should calculate debt based on outstanding_balance)
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

    // Check total usd value (should be approximately 1 SUI = 2 USD)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        // With 0 days passed, debt should equal outstanding_balance = 1 SUI = 2 USD
        assert!(total_usd_value == 2 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

// ==================== Compound Interest Tests ====================

#[test]
// Should update BridgingFiPosition value with compound interest after multiple days
public fun test_update_bridgingfi_position_value_with_compound_interest() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
        &mut s,
        CUSTODIAN,
        APR_10_PERCENT, // Use 10% APR for more significant interest
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

    // Set initial outstanding_balance and last_update_day to day 0
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let mut position = vault::borrow_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            &mut vault,
            bridgingfi_asset_type,
        );

        bridgingfi_adapter::set_outstanding_balance(&mut position, INITIAL_INVESTMENT);
        bridgingfi_adapter::update_last_update_day(&mut position, 0);

        vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
        test_scenario::return_shared(vault);
    };

    // Advance clock by 30 days and update oracle price
    s.next_tx(OWNER);
    {
        clock::set_for_testing(&mut clock, 30 * 24 * 3600 * 1000);
        let mut oracle_config = s.take_shared<OracleConfig>();
        let sui_asset_type = type_name::get<SUI_TEST_COIN>().into_string();
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            2 * ORACLE_DECIMALS,
        );
        test_scenario::return_shared(oracle_config);
    };

    // Update value (should calculate compound interest for 30 days)
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

    // Check total usd value
    // Expected for 30 days at 10% APR:
    // rate_per_day = 0.10 / 365 = 0.0002739726
    // base = 1.0002739726
    // compounded_rate = base ^ 30 ≈ 1.008256
    // debt = 1_000_000_000 * 1.008256 ≈ 1,008,256,000
    // USD value = 1,008,256,000 / 1e9 * 2 = 2.016512 USD
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        // Expected: approximately 2.016512 * DECIMALS
        let expected_min = 2_016_000_000; // Allow some tolerance
        let expected_max = 2_017_000_000;
        assert!(total_usd_value >= expected_min, 0);
        assert!(total_usd_value <= expected_max, 1);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// Should update BridgingFiPosition value multiple times without changing position state
public fun test_update_bridgingfi_position_value_multiple_updates() {
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

    // Set initial outstanding_balance and last_update_day to day 0
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let mut position = vault::borrow_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            &mut vault,
            bridgingfi_asset_type,
        );

        bridgingfi_adapter::set_outstanding_balance(&mut position, INITIAL_INVESTMENT);
        bridgingfi_adapter::update_last_update_day(&mut position, 0);

        vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
        test_scenario::return_shared(vault);
    };

    // First update after 1 day (update oracle price)
    s.next_tx(OWNER);
    {
        clock::set_for_testing(&mut clock, 1 * 24 * 3600 * 1000);
    };

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let sui_asset_type = type_name::get<SUI_TEST_COIN>().into_string();
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            2 * ORACLE_DECIMALS,
        );
        test_scenario::return_shared(oracle_config);
    };

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

    // Verify position state is NOT updated (still day 0)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            bridgingfi_asset_type,
        );

        // Position state should still be at day 0 (not updated by update_value)
        assert!(bridgingfi_adapter::last_update_day(position) == 0, 0);
        assert!(bridgingfi_adapter::outstanding_balance(position) == INITIAL_INVESTMENT, 1);

        test_scenario::return_shared(vault);
    };

    // Second update after 2 days (update oracle price, should calculate from day 0 to day 2)
    s.next_tx(OWNER);
    {
        clock::set_for_testing(&mut clock, 2 * 24 * 3600 * 1000);
    };

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let sui_asset_type = type_name::get<SUI_TEST_COIN>().into_string();
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            2 * ORACLE_DECIMALS,
        );
        test_scenario::return_shared(oracle_config);
    };

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

    // Verify position state is still NOT updated
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let position = vault.get_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            bridgingfi_asset_type,
        );

        // Position state should still be at day 0
        assert!(bridgingfi_adapter::last_update_day(position) == 0, 0);
        assert!(bridgingfi_adapter::outstanding_balance(position) == INITIAL_INVESTMENT, 1);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

// ==================== Edge Case Tests ====================

#[test]
// Should update BridgingFiPosition value with zero APR
public fun test_update_bridgingfi_position_value_zero_apr() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
        &mut s,
        CUSTODIAN,
        APR_0_PERCENT, // 0% APR
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

    // Set initial outstanding_balance and last_update_day to day 0
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let mut position = vault::borrow_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            &mut vault,
            bridgingfi_asset_type,
        );

        bridgingfi_adapter::set_outstanding_balance(&mut position, INITIAL_INVESTMENT);
        bridgingfi_adapter::update_last_update_day(&mut position, 0);

        vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
        test_scenario::return_shared(vault);
    };

    // Advance clock by 30 days and update oracle price
    s.next_tx(OWNER);
    {
        clock::set_for_testing(&mut clock, 30 * 24 * 3600 * 1000);
        let mut oracle_config = s.take_shared<OracleConfig>();
        let sui_asset_type = type_name::get<SUI_TEST_COIN>().into_string();
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            2 * ORACLE_DECIMALS,
        );
        test_scenario::return_shared(oracle_config);
    };

    // Update value (with 0% APR, debt should remain the same)
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

    // Check total usd value (should be unchanged with 0% APR)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        // With 0% APR, debt should remain 1 SUI = 2 USD
        assert!(total_usd_value == 2 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// Should update BridgingFiPosition value on the same day (no compound interest)
public fun test_update_bridgingfi_position_value_same_day() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    bridgingfi_test_helpers::init_create_bridgingfi_position<SUI_TEST_COIN>(
        &mut s,
        CUSTODIAN,
        APR_10_PERCENT,
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

    // Set initial outstanding_balance and last_update_day to current day
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let mut position = vault::borrow_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            &mut vault,
            bridgingfi_asset_type,
        );

        bridgingfi_adapter::set_outstanding_balance(&mut position, INITIAL_INVESTMENT);
        let current_day = bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock));
        bridgingfi_adapter::update_last_update_day(&mut position, current_day);

        vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
        test_scenario::return_shared(vault);
    };

    // Update value on the same day (should return snapshot debt, no compound interest)
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

    // Check total usd value (should be unchanged, no compound interest)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        // With 0 days passed, debt should equal outstanding_balance = 1 SUI = 2 USD
        assert!(total_usd_value == 2 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

// ==================== Integration Tests ====================

#[test]
// Should update total usd value with BridgingFiPosition
public fun test_update_total_usd_value_with_bridgingfi_position() {
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

    // Set initial outstanding_balance
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
        let mut position = vault::borrow_defi_asset<SUI_TEST_COIN, BridgingFiPosition>(
            &mut vault,
            bridgingfi_asset_type,
        );

        bridgingfi_adapter::set_outstanding_balance(&mut position, INITIAL_INVESTMENT);
        let current_day = bridgingfi_adapter::get_day_index(clock::timestamp_ms(&clock));
        bridgingfi_adapter::update_last_update_day(&mut position, current_day);

        vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
        test_scenario::return_shared(vault);
    };

    // Update BridgingFiPosition value
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

    // Check total usd value (should include BridgingFiPosition value)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        // Should be 1 SUI = 2 USD (BridgingFiPosition value)
        assert!(total_usd_value == 2 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

