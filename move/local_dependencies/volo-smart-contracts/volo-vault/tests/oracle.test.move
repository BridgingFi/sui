#[test_only]
module volo_vault::vault_oracle_test;

use std::type_name;
use sui::clock;
use sui::test_scenario;
use switchboard::aggregator;
use volo_vault::btc_test_coin::BTC_TEST_COIN;
use volo_vault::init_vault;
use volo_vault::mock_aggregator;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::vault::{Vault, AdminCap};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

const OWNER: address = @0xa;

const DECIMALS: u256 = 1_000_000_000;
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000;

#[test]
// [TEST-CASE: Should add switchboard aggregator.] @test-case ORACLE-001
public fun test_add_switchboard_aggregator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_manage::add_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        assert!(oracle_config.coin_decimals(type_name::get<SUI_TEST_COIN>().into_string()) == 9);
        assert!(oracle_config.dex_slippage() == 100);

        let price = oracle_config.get_asset_price(
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        assert!(price == 1_000_000_000_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should get asset price fail if not added.] @test-case ORACLE-002
public fun test_get_asset_price_fail_not_added() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let _price = oracle_config.get_asset_price(
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_PRICE_NOT_UPDATED, location = vault_oracle)]
// [TEST-CASE: Should add switchboard aggregator fail if price not updated.] @test-case ORACLE-003
public fun test_add_switchboard_aggregator_fail_price_not_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        clock::set_for_testing(&mut clock, 1000 *60 + 1);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_AGGREGATOR_ALREADY_EXISTS,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should add switchboard aggregator fail if already added.] @test-case ORACLE-004
public fun test_add_switchboard_aggregator_fail_already_added() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should remove switchboard aggregator.] @test-case ORACLE-005
public fun test_remove_switchboard_aggregator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::remove_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should remove switchboard aggregator fail if already removed.] @test-case ORACLE-006
public fun test_remove_switchboard_aggregator_fail_already_removed() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        vault_oracle::remove_switchboard_aggregator(
            &mut oracle_config,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        vault_oracle::remove_switchboard_aggregator(
            &mut oracle_config,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should update price from aggregator.] @test-case ORACLE-007
public fun test_update_price_from_aggregator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        clock::set_for_testing(&mut clock, 1000 * 60);
        mock_aggregator::set_current_result(&mut aggregator, 2_000_000_000_000_000_000, 1000 * 60);

        vault_oracle::update_price(
            &mut oracle_config,
            &aggregator,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let price = oracle_config.get_asset_price(
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        assert!(price == 2_000_000_000_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should change switchboard aggregator.] @test-case ORACLE-008
public fun test_change_switchboard_aggregator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            18,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 2_000_000_000_000_000_000, 0);

        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::change_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let price = oracle_config.get_asset_price(
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        assert!(price == 2_000_000_000_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should get normalized price for different decimals.] @test-case ORACLE-009
public fun test_get_normalized_price_for_different_decimals() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<USDC_TEST_COIN>().into_string(),
            6,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let normalized_sui_price = oracle_config.get_normalized_asset_price(
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );
        assert!(normalized_sui_price == 1_000_000_000_000_000_000);

        let normalized_usdc_price = oracle_config.get_normalized_asset_price(
            &clock,
            type_name::get<USDC_TEST_COIN>().into_string(),
        );
        assert!(normalized_usdc_price == 1_000_000_000_000_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should get correct usd value with normalized prices.] @test-case ORACLE-010
public fun test_get_correct_usd_value_with_oracle_price_with_different_decimals() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::get<SUI_TEST_COIN>().into_string();
    let usdc_asset_type = type_name::get<USDC_TEST_COIN>().into_string();
    let btc_asset_type = type_name::get<BTC_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();

        assert!(
            vault_oracle::get_asset_price(&config, &clock, sui_asset_type) == 2 * ORACLE_DECIMALS,
        );
        assert!(
            vault_oracle::get_asset_price(&config, &clock, usdc_asset_type) == 1 * ORACLE_DECIMALS,
        );
        assert!(
            vault_oracle::get_asset_price(&config, &clock, btc_asset_type) == 100_000 * ORACLE_DECIMALS,
        );

        assert!(
            vault_oracle::get_normalized_asset_price(&config, &clock, sui_asset_type) == 2 * ORACLE_DECIMALS,
        );
        assert!(
            vault_oracle::get_normalized_asset_price(&config, &clock, usdc_asset_type) == 1 * ORACLE_DECIMALS * 1_000,
        );
        assert!(
            vault_oracle::get_normalized_asset_price(&config, &clock, btc_asset_type) == 100_000 * ORACLE_DECIMALS * 10,
        );

        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();

        let sui_usd_value_for_1_sui = vault_utils::mul_with_oracle_price(
            1_000_000_000,
            vault_oracle::get_normalized_asset_price(&config, &clock, sui_asset_type),
        );

        let usdc_usd_value_for_1_usdc = vault_utils::mul_with_oracle_price(
            1_000_000,
            vault_oracle::get_normalized_asset_price(&config, &clock, usdc_asset_type),
        );

        let btc_usd_value_for_1_btc = vault_utils::mul_with_oracle_price(
            100_000_000,
            vault_oracle::get_normalized_asset_price(&config, &clock, btc_asset_type),
        );

        assert!(sui_usd_value_for_1_sui == 2 * DECIMALS);
        assert!(usdc_usd_value_for_1_usdc == 1 * DECIMALS);
        assert!(btc_usd_value_for_1_btc == 100_000 * DECIMALS);

        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[
    test,
    expected_failure(
        abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should change switchboard aggregator fail if asset type not found.] @test-case ORACLE-011
public fun test_change_switchboard_aggregator_fail_asset_type_not_found() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            18,
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 2_000_000_000_000_000_000, 0);

        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::change_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            type_name::get<USDC_TEST_COIN>().into_string(),
            &aggregator,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        aggregator::destroy_aggregator(aggregator);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[
    test,
    expected_failure(
        abort_code = vault_oracle::ERR_AGGREGATOR_ASSET_MISMATCH,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should update price fail if aggregator asset mismatch.] @test-case ORACLE-012
public fun test_update_price_fail_aggregator_asset_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        clock::set_for_testing(&mut clock, 1000 * 60);
        mock_aggregator::set_current_result(&mut aggregator, 2_000_000_000_000_000_000, 1000 * 60);

        let mut wrong_aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(
            &mut wrong_aggregator,
            2_000_000_000_000_000_000,
            1000 * 60,
        );

        vault_oracle::update_price(
            &mut oracle_config,
            &wrong_aggregator,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
        aggregator::destroy_aggregator(wrong_aggregator);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should update price when max timestamp larger than current timestamp.] @test-case ORACLE-013
public fun test_update_price_when_max_timestamp_larger_than_current_timestamp() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut aggregator = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut aggregator, 1_000_000_000_000_000_000, 0);

        vault_oracle::add_switchboard_aggregator(
            &mut oracle_config,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
            9,
            &aggregator,
        );

        clock::set_for_testing(&mut clock, 1000 * 60 - 1);
        mock_aggregator::set_current_result(&mut aggregator, 2_000_000_000_000_000_000, 1000 * 60);

        vault_oracle::update_price(
            &mut oracle_config,
            &aggregator,
            &clock,
            type_name::get<SUI_TEST_COIN>().into_string(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);

        aggregator::destroy_aggregator(aggregator);
    };

    clock::destroy_for_testing(clock);
    s.end();
}