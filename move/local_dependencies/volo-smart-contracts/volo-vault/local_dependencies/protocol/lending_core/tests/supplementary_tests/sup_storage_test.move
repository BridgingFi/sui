#[test_only]
module lending_core::sup_storage_test {
    use std::vector;
    use sui::clock;
    use sui::coin::{CoinMetadata};
    use sui::test_scenario::{Self};

    use lending_core::global;
    use lending_core::sup_global;

    use lending_core::pool::{Self, Pool, PoolAdminCap};
    use lending_core::btc_test::{BTC_TEST};
    use lending_core::usdt_test::{USDT_TEST};
    use lending_core::usdc_test::{USDC_TEST};
    use lending_core::eth_test::{ETH_TEST};
    use lending_core::eth2_test::{Self, ETH2_TEST};

    use lending_core::lib::{Self};
    use lending_core::logic::{Self};
    use oracle::oracle::{PriceOracle, OracleFeederCap, OracleAdminCap, Self};

    use math::ray_math;

    use sui::coin::{Self, Coin};
    use lending_core::storage::{Self, Storage, OwnerCap, StorageAdminCap};
    const OWNER: address = @0xA;

    #[test]
    public fun test_sup_setters_getters() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            assert!(storage::pause(&stg) == false, 0);
            storage::when_not_paused(&stg);
            storage::set_pause(&owner_cap, &mut stg, true);
            assert!(storage::pause(&stg) == true, 0);

            storage::set_supply_cap(&owner_cap,&mut stg, 0, 3000000000000_000000000_000000000000000000000000000);
            assert!(storage::get_supply_cap_ceiling(&mut stg, 0) == 3000000000000_000000000_000000000000000000000000000, 0);

            storage::set_borrow_cap(&owner_cap,&mut stg, 0, 800000000000000000000000000);
            assert!(storage::get_borrow_cap_ceiling_ratio(&mut stg, 0) == 800000000000000000000000000, 0);

            storage::set_ltv(&owner_cap,&mut stg, 0, 800000000000000000000000000);
            assert!(storage::get_asset_ltv(&stg, 0) == 800000000000000000000000000, 0);

            storage::set_treasury_factor(&owner_cap,&mut stg, 0, 90000000000000000000000000);
            assert!(storage::get_treasury_factor(&mut stg, 0) == 90000000000000000000000000, 0);

            storage::set_base_rate(&owner_cap,&mut stg, 0, 15000000000000000000000000);
            storage::set_multiplier(&owner_cap,&mut stg, 0, 40000000000000000000000000);
            storage::set_jump_rate_multiplier(&owner_cap,&mut stg, 0, 1080000000000000000000000000);
            storage::set_reserve_factor(&owner_cap,&mut stg, 0, 60000000000000000000000000);
            storage::set_optimal_utilization(&owner_cap,&mut stg, 0, 900000000000000000000000000);

            let (base_f, mul, jump_mul, reserve_f, opt_util) = storage::get_borrow_rate_factors(&mut stg, 0);
            assert!(base_f == 15000000000000000000000000, 2);
            assert!(mul == 40000000000000000000000000, 2);
            assert!(jump_mul == 1080000000000000000000000000, 2);
            assert!(reserve_f == 60000000000000000000000000, 2);
            assert!(opt_util == 900000000000000000000000000, 2);

            storage::set_liquidation_ratio(&owner_cap,&mut stg, 0, 340000000000000000000000000);
            storage::set_liquidation_bonus(&owner_cap,&mut stg, 0, 35000000000000000000000000);
            storage::set_liquidation_threshold(&owner_cap,&mut stg, 0, 900000000000000000000000000);
            let (ratio, bonus, threshold) = storage::get_liquidation_factors(&mut stg, 0);
            assert!(ratio == 340000000000000000000000000, 2);
            assert!(bonus == 35000000000000000000000000, 2);
            assert!(threshold == 900000000000000000000000000, 2);

            assert!(storage::get_reserves_count(&stg) == 6, 0);

            assert!(storage::get_last_update_timestamp(&stg, 0) == 0, 2);
            storage::update_state_for_testing(&mut stg, 0, 1, 1, 1, 1);
            assert!(storage::get_last_update_timestamp(&stg, 0) == 1, 2);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1701, location=lending_core::storage)]
    // Should pass reserve_validation
    public fun test_pass_reserve_validation() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<BTC_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            storage::reserve_validation<BTC_TEST>(&stg);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should different balances in pool can be increased and decreased
    public fun test_increase_balance_for_pool() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);

            let (total_supply_balance_before, total_borrow_balance_before) = storage::get_total_supply(&mut stg, 0);
            assert!(total_supply_balance_before == 0, 0);
            assert!(total_borrow_balance_before == 0, 0);

            storage::increase_balance_for_pool_for_testing(&mut stg, 0, 50_000000000, 100_000000000);

            let (total_supply_balance_after, total_borrow_balance_after) = storage::get_total_supply(&mut stg, 0);
            assert!(total_supply_balance_after == 50_000000000, 0);
            assert!(total_borrow_balance_after == 100_000000000, 0);

            test_scenario::return_shared(stg);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should increase_treasury_balance
    public fun test_increase_treasury_balance() {
                let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);

            let b_before = storage::get_treasury_balance(&stg, 0);

            storage::increase_treasury_balance_for_testing(&mut stg, 0, 50_000000000);

            let b_after = storage::get_treasury_balance(&stg, 0);

            assert!(b_before == 0, 0);
            assert!(b_after == 50_000000000, 0);

            test_scenario::return_shared(stg);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should not remove if asset is not user's loan
    public fun test_remove_not_user_loans() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);

            storage::update_user_loans_for_testing(&mut stg, 0, OWNER);

            test_scenario::return_shared(stg);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);

            let (_, loans) = storage::get_user_assets(&stg, OWNER);
            let loans_before = vector::empty<u8>();
            vector::push_back(&mut loans_before, 0);
            assert!(loans == loans_before, 0);

            storage::remove_user_loans_for_testing(&mut stg, 1, OWNER);

            let (_, loans) = storage::get_user_assets(&stg, OWNER);
            assert!(loans == loans_before, 0);

            test_scenario::return_shared(stg);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should not remove if it is not user's collaterals
    public fun test_remove_not_user_collaterals() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);

            storage::update_user_collaterals_for_testing(&mut stg, 0, OWNER);

            test_scenario::return_shared(stg);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);

            let (collaterals, _) = storage::get_user_assets(&stg, OWNER);
            let collaterals_before = vector::empty<u8>();
            vector::push_back(&mut collaterals_before, 0);
            assert!(collaterals == collaterals_before, 0);

            storage::remove_user_collaterals_for_testing(&mut stg, 1, OWNER);

            let (collaterals, _) = storage::get_user_assets(&stg, OWNER);
            assert!(collaterals == collaterals_before, 0);

            test_scenario::return_shared(stg);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should withdraw successfully for enough balance in pool
    // Should withdraw correct amount and decrease balance
    public fun test_withdraw_treasury1() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<ETH_TEST>>(&scenario); 
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            storage::update_state_for_testing(&mut stg, 1, math::ray_math::ray(), math::ray_math::ray(), 1, 100_000000000);
            storage::increase_total_supply_balance_for_testing(&mut stg, 1, 100_000000000);
            let coin = coin::mint_for_testing<ETH_TEST>(10_000000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            let (s) = storage::get_treasury_balance(&mut stg, 1);
            assert!(s == 100_000000000, 0);
            let (s, b) = storage::get_total_supply(&mut stg, 1);
            assert!(s == 100_000000000 && b == 0, 0);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 1, &mut pool, 1_000000000, OWNER, ctx);

            let (s) = storage::get_treasury_balance(&mut stg, 1);
            assert!(s == 99_000000000, 0);
            let (s, b) = storage::get_total_supply(&mut stg, 1);
            assert!(s == 99_000000000 && b == 0, 0);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<ETH_TEST>>(&scenario);
            assert!(coin::value(&c) == 1_000000000, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should withdraw successfully for enough balance in pool
    // Should withdraw correct amount and decrease balance (SUI)
    public fun test_withdraw_treasury2() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario); 
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            storage::update_state_for_testing(&mut stg, 3, math::ray_math::ray(), math::ray_math::ray(), 1, 100_000000000);
            storage::increase_total_supply_balance_for_testing(&mut stg, 3, 100_000000000);
            let coin = coin::mint_for_testing<USDC_TEST>(100_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            let (s) = storage::get_treasury_balance(&mut stg, 3);
            assert!(s == 100_000000000, 0);
            let (s, b) = storage::get_total_supply(&mut stg, 3);
            assert!(s == 100_000000000 && b == 0, 0);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 3, &mut pool, 99_000000, OWNER, ctx);

            let (s) = storage::get_treasury_balance(&mut stg, 3);
            assert!(s == 1_000000000, 0);
            let (s, b) = storage::get_total_supply(&mut stg, 3);
            // after fixing: 0
            assert!(s == 1_000000000 && b == 0, 0);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<USDC_TEST>>(&scenario);
            assert!(coin::value(&c) == 99_000000, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should withdraw correct amount and decrease balance when index > 1
    public fun test_withdraw_treasury_with_index_changed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario); 
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            // borrow, supply index = 3, 2
            storage::update_state_for_testing(&mut stg, 0, math::ray_math::ray() * 3, math::ray_math::ray() * 2, 1, 100_000000000);
            storage::increase_total_supply_balance_for_testing(&mut stg, 0, 200_000000000);
            let coin = coin::mint_for_testing<USDT_TEST>(100_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            let (s) = storage::get_treasury_balance(&mut stg, 0);
            assert!(s == 100_000000000, 0);
            let (s, b) = storage::get_total_supply(&mut stg, 0);
            assert!(s == 200_000000000 && b == 0, 0);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 100_000000, OWNER, ctx);

            let (s) = storage::get_treasury_balance(&mut stg, 0);
            assert!(s == 50_000000000, 0);
            let (s, b) = storage::get_total_supply(&mut stg, 0);
            // after fixing: 150_000000000
            assert!(s == 150_000000000 && b == 0, 0);

            // index remains the same
            let (s, b) = storage::get_index(&mut stg, 0);
            assert!(s == 2 * ray_math::ray() && b == 3 * ray_math::ray(), 0);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            assert!(coin::value(&c) == 100_000000, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    }
    #[test]
    // Should withdraw max withdrawable amount for not enough balance in pool
    // Should withdraw max if input amount more than treasury
    public fun test_withdraw_treasury_exceed_balance() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            storage::update_state_for_testing(&mut stg, 0, ray_math::ray(), ray_math::ray(), 0, 99_000000000);
            storage::increase_total_supply_balance_for_testing(&mut stg, 0, 99_000000000);

            let coin = coin::mint_for_testing<USDT_TEST>(100_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 100_000000, OWNER, ctx);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c));
            assert!(coin::value(&c) == 99_000000, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    } 
    
    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::pool)]
    // Should withdraw fail for not enough reserve balance in pool
    public fun test_withdraw_treasury_exceed_reserve_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            storage::update_state_for_testing(&mut stg, 0, ray_math::ray(), ray_math::ray(), 0, 100_000000000);
            storage::increase_total_supply_balance_for_testing(&mut stg, 0, 100_000000000);

            let coin = coin::mint_for_testing<USDT_TEST>(99_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 100_000000, OWNER, ctx);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c));
            assert!(coin::value(&c) == 100_000000, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    } 
    
    #[test]
    // Should withdraw 0 if balance = 0 for input amount = 0 and amount > 0
    public fun test_withdraw_treasury_zero() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        // try withdraw 0
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            let coin = coin::mint_for_testing<USDT_TEST>(100_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 0, OWNER, ctx);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c));
            assert!(coin::value(&c) == 0, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        // try withdraw 1
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 1, OWNER, ctx);

            test_scenario::return_shared(pool);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c));
            assert!(coin::value(&c) == 0, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    } 

    /* 
        1. A deposit and borrow in multiple pools
        2. Time passes for a year, treasury increases
        3. Withdraw half balance
        4. Time passes for a year, treasury increases
        5. Should withdraw all balance successfully
        5b. Should fail to withdraw again
        6. compare wtih the data in control group, including index, balance, fund balance, rate, treasury
        add liquidation bonus part
    */
    #[test]
    public fun test_withdraw_balance_integration_1() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000000);

            // deposit 10000U 
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  
            // borrow 9000U
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 9000_000000000);

            lib::printf(b"past 1 year");
            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_for_testing(&clock, &mut stg, 0);

            lib::print_index(&mut stg, 0); // 1124713000000000000000000000 1160649354904960155468616000

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            //  10000 + 9000 * (1.16 - 1) * 0.07 / 1.1247
            lib::close_to(s, 10089_600000000, 0);
            assert!(b == 9000_000000000, 0);

            let  treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // supply - 10000
            lib::close_to(treasury, 89_600000000, 0);

            let coin = coin::mint_for_testing<USDT_TEST>(1000_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            lib::print_balance(&mut stg, 0);

            // withdraw 50
            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 50_000000, OWNER, ctx);

            let treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // 89.6 - 50 / 1.1247
            lib::close_to(treasury, 45_100000000, 0);

            lib::printf(b"past 1 year");
            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_of_all_for_testing(&clock, &mut stg);
            // before fixing: 1264979332369000000000000000 1347106925041300156499730338
            lib::print_index(&mut stg, 0); // 1264979332369000000000000000 1347106925041300156499730338


            let treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // 45.1 + 9000 * (1.347 - 1.1606) * 0.07 / 1.2649
            lib::close_to(treasury, 137_900000000, 0);

            // withdraw all
            // 138.39(actual balance) * 1.26497 = 175.05
            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 175_600000, OWNER, ctx);
            let treasury = storage::get_treasury_balance(&mut stg, 0);
            assert!(treasury == 0, 0);

            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 175_600000, OWNER, ctx);
            let treasury = storage::get_treasury_balance(&mut stg, 0);
            assert!(treasury == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            lib::print(&s);
            // before fixing: 138 + 50 / 1.12 + 10000 ~= 10182
            lib::close_to(s, 10000_000000000, 0);

            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c1 = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c1));
            
            let c2 = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c2));

            let c3 = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            lib::print(&coin::value(&c3));

            // 0
            lib::close_to(0, (coin::value(&c1) as u256), 1000000);
            // 175.05
            lib::close_to(175_050000, (coin::value(&c2) as u256), 0_500000);
            // 50
            lib::close_to(50_000000, (coin::value(&c3) as u256), 1);
            test_scenario::return_to_sender(&scenario, c1);
            test_scenario::return_to_sender(&scenario, c2);
            test_scenario::return_to_sender(&scenario, c3);

        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_withdraw_balance_integration_2() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);
        let ctx = test_scenario::ctx(&mut scenario);
        let clock = clock::create_for_testing(ctx);

        // deposit adn pass 1 year
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);

            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000000);

            // deposit 10000U 
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  
            // borrow 9000U
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 9000_000000000);

            lib::printf(b"past 1 year");
            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_for_testing(&clock, &mut stg, 0);

            lib::print_index(&mut stg, 0); // 1124713000000000000000000000 1160649354904960155468616000

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            //  10000 + 9000 * (1.16 - 1) * 0.07 / 1.1247
            lib::close_to(s, 10089_600000000, 0);
            assert!(b == 9000_000000000, 0);

            let  treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // supply - 10000
            lib::close_to(treasury, 89_600000000, 0);

            let coin = coin::mint_for_testing<USDT_TEST>(100_000000, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            // withdraw 50
            storage::withdraw_treasury(&storage_admin_cap, &pool_admin_cap, &mut stg, 0, &mut pool, 50_000000, OWNER, ctx);

            let  treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // 89.6 - 50 / 1.1247
            lib::close_to(treasury, 45_100000000, 0);

            lib::printf(b"past 1 year");
            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_of_all_for_testing(&clock, &mut stg);
            lib::print_index(&mut stg, 0); // 1264979332369000000000000000 1347106925041300156499730338

            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
        };

        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_borrow_cap_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_borrow_cap(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_treasury_factor_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_treasury_factor(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_reserve_factor_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_reserve_factor(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_optimal_utilization_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_optimal_utilization(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_liquidation_bonus_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_liquidation_bonus(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_liquidation_ratio_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_liquidation_ratio(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_ltv_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_ltv(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_set_liquidation_threshold_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);

            storage::set_liquidation_threshold(&owner_cap,&mut stg, 0, ray_math::ray() + 1);

            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }


    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_borrow_cap_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray() + 1, // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                750000000000000000000000000, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                350000000000000000000000000, // liquidation_ratio: 35%
                50000000000000000000000000, // liquidation_bonus: 5%
                800000000000000000000000000, // liquidation_threshold: 80%
                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_treasury_factor_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                750000000000000000000000000, // ltv: 75%
                ray_math::ray() + 1, // borrow_cap_ceiling: 90%
                350000000000000000000000000, // liquidation_ratio: 35%
                50000000000000000000000000, // liquidation_bonus: 5%
                800000000000000000000000000, // liquidation_threshold: 80%
                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_reserve_factor_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                ray_math::ray() + 1,
                750000000000000000000000000, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                350000000000000000000000000, // liquidation_ratio: 35%
                50000000000000000000000000, // liquidation_bonus: 5%
                800000000000000000000000000, // liquidation_threshold: 80%
                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_optimal_utilization_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                ray_math::ray() + 1, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                750000000000000000000000000, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                350000000000000000000000000, // liquidation_ratio: 35%
                50000000000000000000000000, // liquidation_bonus: 5%
                800000000000000000000000000, // liquidation_threshold: 80%
                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_liquidation_bonus_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                750000000000000000000000000, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                350000000000000000000000000, // liquidation_ratio: 35%
                ray_math::ray() + 1, 
                800000000000000000000000000, // liquidation_threshold: 80%
                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_liquidation_ratio_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                750000000000000000000000000, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                ray_math::ray() + 1,
                ray_math::ray(), // liquidation_bonus: 5%
                0, // borrow_cap_ceiling: 90%, // liquidation_threshold: 80%
                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_ltv_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                ray_math::ray() + 1, // borrow_cap_ceiling: 90%, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                ray_math::ray(), 
                ray_math::ray(), // liquidation_bonus: 5%
                0,                &metadata, // metadata
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1507, location=lending_core::storage)]
    public fun test_init_liquidation_threshold_failed() {
        let scenario = test_scenario::begin(OWNER);
        {
            sup_global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            eth2_test::init_for_testing(test_scenario::ctx(&mut scenario)); 
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            let storage_admin_cap = test_scenario::take_from_sender<StorageAdminCap>(&scenario);
            let metadata = test_scenario::take_immutable<CoinMetadata<ETH2_TEST>>(&scenario);

            storage::init_reserve<ETH2_TEST>(
                &storage_admin_cap,
                &pool_admin_cap,
                &clock,
                &mut stg,
                3, // oracle id
                false, // is_isolated
                175000000000000000000000000000000000000, // supply_cap_ceiling: 20000000
                ray_math::ray(), // borrow_cap_ceiling: 90%
                0, // base_rate: 0%
                750000000000000000000000000, // optimal_utilization: 80%
                86000000000000000000000000, // multiplier: 5%
                3200000000000000000000000000, // jump_rate_multiplier: 109%
                200000000000000000000000000, // reserve_factor: 7%
                750000000000000000000000000, // ltv: 75%
                100000000000000000000000000, // treasury_factor: 10%
                ray_math::ray(), 
                ray_math::ray(), 
                ray_math::ray() + 1, 
                &metadata, 
                test_scenario::ctx(&mut scenario)
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_immutable(metadata);
            test_scenario::return_to_sender(&scenario, pool_admin_cap);
            test_scenario::return_to_sender(&scenario, storage_admin_cap);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::end(scenario);
    }
}
