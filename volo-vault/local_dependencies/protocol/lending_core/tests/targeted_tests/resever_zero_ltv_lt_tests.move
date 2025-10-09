#[test_only]
module lending_core::reseve_global {
    use sui::clock;
    use sui::coin::{CoinMetadata};
    use sui::test_scenario::{Self, Scenario};

    use oracle::oracle::{Self, OracleAdminCap, PriceOracle};
    use lending_core::incentive;
    use lending_core::pool::{Self, PoolAdminCap};
    use lending_core::eth_test::{Self, ETH_TEST};
    use lending_core::usdt_test::{Self, USDT_TEST};
    use lending_core::storage::{Self, Storage, StorageAdminCap};


    const USDT_DECIMALS: u8 = 9;
    const USDT_ORACLE_ID: u8 = 0;
    const USDT_INITIAL_PRICE: u256 = 1_000000000;

    const ETH_DECIMALS: u8 = 9;
    const ETH_ORACLE_ID: u8 = 1;
    const ETH_INITIAL_PRICE: u256 = 1800_000000000;

    #[test_only]
    public fun init_protocol(scenario_mut: &mut Scenario) {
        let owner = test_scenario::sender(scenario_mut);

        // Protocol init
        test_scenario::next_tx(scenario_mut, owner);
        {
            pool::init_for_testing(test_scenario::ctx(scenario_mut));      // Initialization of pool
            storage::init_for_testing(test_scenario::ctx(scenario_mut));   // Initialization of storage
            oracle::init_for_testing(test_scenario::ctx(scenario_mut));    // Initialization of oracel
            eth_test::init_for_testing(test_scenario::ctx(scenario_mut));  // Initialization of ETH coin
            usdt_test::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of USDT coin

            incentive::init_for_testing(test_scenario::ctx(scenario_mut)); // Initialization of incentive
        };

        // Oracle: Init
        test_scenario::next_tx(scenario_mut, owner);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(scenario_mut));
            let price_oracle = test_scenario::take_shared<PriceOracle>(scenario_mut);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(scenario_mut);

            // register USDT token
            oracle::register_token_price(
                &oracle_admin_cap,
                &clock,
                &mut price_oracle,
                USDT_ORACLE_ID,
                USDT_INITIAL_PRICE,
                USDT_DECIMALS,
            );

            // register ETH token
            oracle::register_token_price(
                &oracle_admin_cap,
                &clock,
                &mut price_oracle,
                ETH_ORACLE_ID,
                ETH_INITIAL_PRICE,
                ETH_DECIMALS,
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(scenario_mut, oracle_admin_cap);
        };

        // Protocol: Adding USDT pools
        test_scenario::next_tx(scenario_mut, owner);
        {
            let storage = test_scenario::take_shared<Storage>(scenario_mut);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario_mut));
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(scenario_mut);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(scenario_mut);
            let usdt_metadata = test_scenario::take_immutable<CoinMetadata<USDT_TEST>>(scenario_mut);
            
            storage::init_reserve<USDT_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut storage,
                USDT_ORACLE_ID,                                   // oracle id
                false,                                           // is_isolated
                2000000000000_000000000_000000000000000000000000000,  // supply_cap_ceiling: 20000000
                900000000000000000000000000,                     // borrow_cap_ceiling: 90%
                0,                                               // base_rate: 0%
                800000000000000000000000000,                     // optimal_utilization: 80%
                50000000000000000000000000,                      // multiplier: 5%
                1090000000000000000000000000,                     // jump_rate_multiplier: 109%
                70000000000000000000000000,                     // reserve_factor: 7%
                800000000000000000000000000,                     // ltv: 80%
                100000000000000000000000000,                     // treasury_factor: 10%
                350000000000000000000000000,                     // liquidation_ratio: 35%
                50000000000000000000000000,                      // liquidation_bonus: 5%
                850000000000000000000000000,                     // liquidation_threshold: 85%
                &usdt_metadata,                                  // metadata
                test_scenario::ctx(scenario_mut)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_immutable(usdt_metadata);
            test_scenario::return_to_sender(scenario_mut, pool_admin_cap);
            test_scenario::return_to_sender(scenario_mut, storage_admin_cap);
        };

        // Protocol: Adding ETH pools
        test_scenario::next_tx(scenario_mut, owner);
        {
            let storage = test_scenario::take_shared<Storage>(scenario_mut);
            let clock = clock::create_for_testing(test_scenario::ctx(scenario_mut));
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(scenario_mut);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(scenario_mut);
            let eth_metadata = test_scenario::take_immutable<CoinMetadata<ETH_TEST>>(scenario_mut);

            storage::init_reserve<ETH_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut storage,
                ETH_ORACLE_ID,                                   // oracle id
                false,                                           // is_isolated
                2000000000_000000000_000000000000000000000000000,  // supply_cap_ceiling: 20000000
                0,                     // borrow_cap_ceiling: 90%
                0,                      // base_rate: 1%
                800000000000000000000000000,                     // optimal_utilization: 80%
                40000000000000000000000000,                      // multiplier: 4%
                800000000000000000000000000,                    // jump_rate_multiplier: 80%
                100000000000000000000000000,                     // reserve_factor: 10%
                0,                     // ltv: 70%
                100000000000000000000000000,                     // treasury_factor: 10%
                350000000000000000000000000,                     // liquidation_ratio: 35%
                50000000000000000000000000,                      // liquidation_bonus: 5%
                750000000000000000000000000,                     // liquidation_threshold: 75%
                &eth_metadata,                                   // metadata
                test_scenario::ctx(scenario_mut)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_immutable(eth_metadata);
            test_scenario::return_to_sender(scenario_mut, pool_admin_cap);
            test_scenario::return_to_sender(scenario_mut, storage_admin_cap);
        };
    }
}


#[test_only]
#[allow(unused_variable, unused_use)]
module lending_core::reseve_zero {
    use sui::clock;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, Scenario};
    use sui::address;

    use math::ray_math;
    use oracle::oracle::{Self, PriceOracle, OracleFeederCap};
    use lending_core::base;
    use lending_core::logic::{Self};
    use lending_core::pool::{Self, Pool};
    use lending_core::usdt_test::{Self, USDT_TEST};
    use lending_core::eth_test::{Self, ETH_TEST};

    use lending_core::incentive_v2::{Self, OwnerCap, Incentive, IncentiveFundsPool};
    use lending_core::incentive::{Incentive as IncentiveV1};
    use utils::utils;
    use sui::transfer;

    use lending_core::lib;

    use lending_core::base_lending_tests::{Self};
    use lending_core::storage::{Self, Storage, OwnerCap as StorageOwnerCap};
    use lending_core::reseve_global;

    const OWNER: address = @0xA;

    #[test] 
    public fun test_deposit_zero_reserve() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            reseve_global::init_protocol(&mut scenario);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<ETH_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 1, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };


        // withdraw
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_withdraw_for_testing(&mut scenario, &clock, &mut pool, 1, 10_000000000);

            // validation
            let (total_supply, _, _) = pool::get_pool_info<ETH_TEST>(&pool);
            assert!(total_supply == 90_000000000, 0);

            // test_scenario::return_shared(price_oracle);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };


        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);

            let hf = logic::user_health_factor(&_clock, &mut storage, &price_oracle, OWNER);

            assert!(hf == address::max(), 0);

            test_scenario::return_shared(storage);
            test_scenario::return_shared(pool);
        test_scenario::return_shared(price_oracle);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test] 
    #[expected_failure(abort_code = 1603, location=lending_core::logic)]
    public fun test_fail_borrow_zero_reserve() {
        let scenario = test_scenario::begin(OWNER);
        let userA = @0xAC;

        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            reseve_global::init_protocol(&mut scenario);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<ETH_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 1, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 0, 10_000000000);
            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 90_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test] 
    #[expected_failure(abort_code = 1605, location=lending_core::validation)]
    public fun test_fail_borrow_out_zero_reserve() {
        let scenario = test_scenario::begin(OWNER);
        let userA = @0xAC;

        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            reseve_global::init_protocol(&mut scenario);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<ETH_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 1, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, userA);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 1, 1_0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }
    
    #[test] 
    public fun test_borrow_out_with_zero_reserve() {
        let scenario = test_scenario::begin(OWNER);

        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            reseve_global::init_protocol(&mut scenario);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // deposit
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<ETH_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 1, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 0, 1_0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }
}