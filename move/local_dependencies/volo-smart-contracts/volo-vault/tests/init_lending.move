#[test_only]
#[allow(unused_let_mut, unused_use)]
module volo_vault::init_lending;

use lending_core::incentive;
use lending_core::incentive_v2::{Self, OwnerCap as IncentiveOwnerCap};
use lending_core::incentive_v3;
use lending_core::pool::{Self, PoolAdminCap};
use lending_core::storage::{Self, Storage, StorageAdminCap, OwnerCap as StorageOwnerCap};
use volo_vault::btc_test_coin::{Self, BTC_TEST_COIN};
use volo_vault::sui_test_coin::{Self, SUI_TEST_COIN};
use volo_vault::usdc_test_coin::{Self, USDC_TEST_COIN};
use oracle::oracle::{Self, OracleAdminCap, PriceOracle};
use sui::clock::{Self, Clock};
use sui::coin::CoinMetadata;
use sui::test_scenario::{Self, Scenario};

const SUI_DECIMALS: u8 = 9;
const SUI_ORACLE_ID: u8 = 0;
const SUI_INITIAL_PRICE: u256 = 4_000000000;

const USDC_DECIMALS: u8 = 6;
const USDC_ORACLE_ID: u8 = 1;
const USDC_INITIAL_PRICE: u256 = 1_000000;

const BTC_DECIMALS: u8 = 8;
const BTC_ORACLE_ID: u8 = 2;
const BTC_INITIAL_PRICE: u256 = 100000_00000000;

#[test_only]
public fun init_protocol(scenario_mut: &mut Scenario, clock: &mut Clock) {
    let owner = test_scenario::sender(scenario_mut);

    // Protocol init
    test_scenario::next_tx(scenario_mut, owner);
    {
        pool::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of pool
        storage::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of storage
        oracle::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of oracel
        sui_test_coin::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of coin
        usdc_test_coin::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of coin
        btc_test_coin::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of coin
        incentive::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of incentive
    };

    // Incentive: Init Cap
    test_scenario::next_tx(scenario_mut, owner);
    {
        let storage_owner_cap = test_scenario::take_from_sender<StorageOwnerCap>(scenario_mut);
        incentive_v2::create_and_transfer_owner(
            &storage_owner_cap,
            test_scenario::ctx(scenario_mut),
        );
        test_scenario::return_to_sender(scenario_mut, storage_owner_cap);
    };

    // Incentive v2: Init
    test_scenario::next_tx(scenario_mut, owner);
    {
        let owner_cap = test_scenario::take_from_sender<IncentiveOwnerCap>(scenario_mut);
        incentive_v2::create_incentive(&owner_cap, test_scenario::ctx(scenario_mut));
        test_scenario::return_to_sender(scenario_mut, owner_cap);
    };

    test_scenario::next_tx(scenario_mut, owner);
    {
        incentive_v3::init_for_testing(test_scenario::ctx(scenario_mut));
    };

    // Oracle: Init
    test_scenario::next_tx(scenario_mut, owner);
    {
        let mut price_oracle = test_scenario::take_shared<PriceOracle>(scenario_mut);
        let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(scenario_mut);

        // set long valid time
        oracle::set_update_interval(
            &oracle_admin_cap,
            &mut price_oracle,
            60 * 60 * 24 * 3650 * 1000,
        );

        oracle::register_token_price(
            &oracle_admin_cap,
            clock,
            &mut price_oracle,
            SUI_ORACLE_ID,
            SUI_INITIAL_PRICE,
            SUI_DECIMALS,
        );

        // register ETH token
        oracle::register_token_price(
            &oracle_admin_cap,
            clock,
            &mut price_oracle,
            USDC_ORACLE_ID,
            USDC_INITIAL_PRICE,
            USDC_DECIMALS,
        );

        // register BTC token
        oracle::register_token_price(
            &oracle_admin_cap,
            clock,
            &mut price_oracle,
            BTC_ORACLE_ID,
            BTC_INITIAL_PRICE,
            BTC_DECIMALS,
        );

        test_scenario::return_shared(price_oracle);
        test_scenario::return_to_sender(scenario_mut, oracle_admin_cap);
    };

    // Protocol: Adding SUI pools
    test_scenario::next_tx(scenario_mut, owner);
    {
        let mut storage = test_scenario::take_shared<Storage>(scenario_mut);

        let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(scenario_mut);
        let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(scenario_mut);
        let sui_metadata = test_scenario::take_immutable<CoinMetadata<SUI_TEST_COIN>>(
            scenario_mut,
        );

        storage::init_reserve<SUI_TEST_COIN>(
            &storage_admin_cap,
            &pool_admin_cap,
            clock,
            &mut storage,
            SUI_ORACLE_ID, // oracle id
            false, // is_isolated
            20000000_000000000_000000000000000000000000000, // supply_cap_ceiling: 20000000
            900000000000000000000000000, // borrow_cap_ceiling: 90%
            0, // base_rate: 0%
            800000000000000000000000000, // optimal_utilization: 80%
            50000000000000000000000000, // multiplier: 5%
            1090000000000000000000000000, // jump_rate_multiplier: 109%
            70000000000000000000000000, // reserve_factor: 7%
            800000000000000000000000000, // ltv: 80%
            100000000000000000000000000, // treasury_factor: 10%
            350000000000000000000000000, // liquidation_ratio: 35%
            50000000000000000000000000, // liquidation_bonus: 5%
            850000000000000000000000000, // liquidation_threshold: 85%
            &sui_metadata, // metadata
            test_scenario::ctx(scenario_mut),
        );

        test_scenario::return_shared(storage);
        test_scenario::return_immutable(sui_metadata);
        test_scenario::return_to_sender(scenario_mut, pool_admin_cap);
        test_scenario::return_to_sender(scenario_mut, storage_admin_cap);
    };

    // Protocol: Adding USDC pools
    test_scenario::next_tx(scenario_mut, owner);
    {
        let mut storage = test_scenario::take_shared<Storage>(scenario_mut);

        let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(scenario_mut);
        let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(scenario_mut);
        let usdc_metadata = test_scenario::take_immutable<CoinMetadata<USDC_TEST_COIN>>(
            scenario_mut,
        );

        storage::init_reserve<USDC_TEST_COIN>(
            &storage_admin_cap,
            &pool_admin_cap,
            clock,
            &mut storage,
            USDC_ORACLE_ID, // oracle id
            false, // is_isolated
            20000000_000000000_000000000000000000000000000, // supply_cap_ceiling: 20000000
            900000000000000000000000000, // borrow_cap_ceiling: 90%
            10000000000000000000000000, // base_rate: 1%
            800000000000000000000000000, // optimal_utilization: 80%
            40000000000000000000000000, // multiplier: 4%
            800000000000000000000000000, // jump_rate_multiplier: 80%
            100000000000000000000000000, // reserve_factor: 10%
            700000000000000000000000000, // ltv: 70%
            100000000000000000000000000, // treasury_factor: 10%
            350000000000000000000000000, // liquidation_ratio: 35%
            50000000000000000000000000, // liquidation_bonus: 5%
            750000000000000000000000000, // liquidation_threshold: 75%
            &usdc_metadata, // metadata
            test_scenario::ctx(scenario_mut),
        );

        test_scenario::return_shared(storage);
        test_scenario::return_immutable(usdc_metadata);
        test_scenario::return_to_sender(scenario_mut, pool_admin_cap);
        test_scenario::return_to_sender(scenario_mut, storage_admin_cap);
    };

    // Protocol: Adding BTC pools
    test_scenario::next_tx(scenario_mut, owner);
    {
        let mut storage = test_scenario::take_shared<Storage>(scenario_mut);

        let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(scenario_mut);
        let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(scenario_mut);
        let btc_metadata = test_scenario::take_immutable<CoinMetadata<BTC_TEST_COIN>>(scenario_mut);

        storage::init_reserve<BTC_TEST_COIN>(
            &storage_admin_cap,
            &pool_admin_cap,
            clock,
            &mut storage,
            BTC_ORACLE_ID, // oracle id
            false, // is_isolated
            20000000_000000000_000000000000000000000000000, // supply_cap_ceiling: 20000000
            900000000000000000000000000, // borrow_cap_ceiling: 90%
            0, // base_rate: 0%
            800000000000000000000000000, // optimal_utilization: 80%
            80000000000000000000000000, // multiplier: 8%
            3000000000000000000000000000, // jump_rate_multiplier: 300%
            100000000000000000000000000, // reserve_factor: 10%
            750000000000000000000000000, // ltv: 75%
            100000000000000000000000000, // treasury_factor: 10%
            350000000000000000000000000, // liquidation_ratio: 35%
            50000000000000000000000000, // liquidation_bonus: 5%
            800000000000000000000000000, // liquidation_threshold: 80%
            &btc_metadata, // metadata
            test_scenario::ctx(scenario_mut),
        );

        test_scenario::return_shared(storage);
        test_scenario::return_immutable(btc_metadata);
        test_scenario::return_to_sender(scenario_mut, pool_admin_cap);
        test_scenario::return_to_sender(scenario_mut, storage_admin_cap);
    };
}
