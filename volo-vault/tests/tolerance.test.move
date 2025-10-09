#[test_only]
module volo_vault::tolerance_test;

use sui::clock;
use sui::coin;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::vault::{Self, Vault, AdminCap};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::OracleConfig;

const OWNER: address = @0xa;

const DEFAULT_LOSS_TOLERANCE: u256 = 10;
const MAX_LOSS_TOLERANCE: u256 = 10_000;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

#[test]
// [TEST-CASE: Should set loss tolerance.] @test-case TOLERANCE-001
public fun test_set_loss_tolerance() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        assert!(vault.loss_tolerance() == DEFAULT_LOSS_TOLERANCE);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_EXCEED_LIMIT, location = vault)]
// [TEST-CASE: Should set loss tolerance fail if exceed max.] @test-case TOLERANCE-002
public fun test_set_loss_tolerance_fail_exceed_max() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.set_loss_tolerance(MAX_LOSS_TOLERANCE + 1);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update loss tolerance.] @test-case TOLERANCE-003
public fun test_update_loss_tolerance() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&oracle_config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    s.next_epoch(OWNER);
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.try_reset_tolerance(false, s.ctx());

        // let usd_value_before = 20_000_000_000_000;
        let loss = 2_000_000_000;

        // Total usd value: 20000u
        // Loss limit: 20000u * 0.02% = 4u
        vault.update_tolerance(loss);

        assert!(vault.cur_epoch_loss() == 2_000_000_000);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.try_reset_tolerance(false, s.ctx());

        // let usd_value_before = 20_000_000_000_000;
        let loss = 2_000_000_000;

        // Total usd value: 20000u
        // Loss limit: 20000u * 0.02% = 4u
        vault.update_tolerance(loss);

        assert!(vault.cur_epoch_loss() == 4_000_000_000);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should reset loss tolerance.] @test-case TOLERANCE-004
public fun test_reset_loss_tolerance() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&oracle_config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    s.next_epoch(OWNER);
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.try_reset_tolerance(false, s.ctx());

        // let usd_value_before = 20_000_000_000_000;
        let loss = 2_000_000_000;

        // Total usd value: 20000u
        // Loss limit: 20000u * 0.02% = 4u
        vault.update_tolerance(loss);

        assert!(vault.cur_epoch_loss() == 2_000_000_000);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.try_reset_tolerance(false, s.ctx());

        // let usd_value_before = 20_000_000_000_000;
        let loss = 2_000_000_000;

        // Total usd value: 20000u
        // Loss limit: 20000u * 0.02% = 4u
        vault.update_tolerance(loss);

        assert!(vault.cur_epoch_loss() == 4_000_000_000);

        test_scenario::return_shared(vault);
    };

    s.next_epoch(OWNER);
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.try_reset_tolerance(false, s.ctx());

        assert!(vault.cur_epoch_loss() == 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should reset loss tolerance by admin.] @test-case TOLERANCE-005
public fun test_reset_loss_tolerance_by_admin() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&oracle_config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    s.next_epoch(OWNER);
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::reset_loss_tolerance(&admin_cap, &mut vault, s.ctx());

        // let usd_value_before = 20_000_000_000_000;
        let loss = 2_000_000_000;

        // Total usd value: 20000u
        // Loss limit: 20000u * 0.02% = 4u
        vault.update_tolerance(loss);

        assert!(vault.cur_epoch_loss() == 2_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    // reset loss tolerance by admin in the same epoch
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::reset_loss_tolerance(&admin_cap, &mut vault, s.ctx());

        assert!(vault.cur_epoch_loss() == 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let loss = 2_000_000_000;
        vault.update_tolerance(loss);
        assert!(vault.cur_epoch_loss() == 2_000_000_000);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}
