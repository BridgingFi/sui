#[test_only]
module lending_core::incentive_v2_more {
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::test_scenario::{Self, Scenario};

    use oracle::oracle::{PriceOracle};
    use lending_core::base::{Self};
    use lending_core::pool::{Self, Pool};
    use lending_core::sui_test::{SUI_TEST};
    use lending_core::usdt_test::{USDT_TEST};
    use lending_core::usdc_test::{USDC_TEST};
    use lending_core::incentive::{Incentive as IncentiveV1};
    use lending_core::storage::{Storage, OwnerCap as StorageOwnerCap};
    use lending_core::incentive_v2::{Self, OwnerCap, Incentive, IncentiveFundsPool};
    use lending_core::incentive_v3::{Self, Incentive as IncentiveV3};

    const OWNER: address = @0xA;

    #[test_only]
    public fun initial_incentive_v2(scenario: &mut Scenario) {
        incentive_v3::init_for_testing(test_scenario::ctx(scenario));

        // create incentive owner cap
        test_scenario::next_tx(scenario, OWNER);
        {
            let storage_owner_cap = test_scenario::take_from_sender<StorageOwnerCap>(scenario);
            incentive_v2::create_and_transfer_owner(&storage_owner_cap, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, storage_owner_cap);
        };
        
        // create incentive
        test_scenario::next_tx(scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);
            incentive_v2::create_incentive(&owner_cap, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, owner_cap);
        };

        // create funds pool
        test_scenario::next_tx(scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);
            let incentive = test_scenario::take_shared<Incentive>(scenario);
            incentive_v2::create_funds_pool<USDC_TEST>(&owner_cap, &mut incentive, 1, false, test_scenario::ctx(scenario));
            incentive_v2::create_funds_pool<USDT_TEST>(&owner_cap, &mut incentive, 2, false, test_scenario::ctx(scenario));

            test_scenario::return_shared(incentive);
            test_scenario::return_to_sender(scenario, owner_cap);
        };

        // increase USDC pool funds
        // increase USDT pool funds
        test_scenario::next_tx(scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);

            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(scenario);
            let coin = coin::mint_for_testing<USDT_TEST>(100000_000000, test_scenario::ctx(scenario));
            incentive_v2::add_funds(&owner_cap, &mut usdt_funds, coin, 100000_000000, test_scenario::ctx(scenario));
            let usdt_before = incentive_v2::get_funds_value(&usdt_funds);
            assert!(usdt_before == 100000_000000, 0);

            let usdc_funds = test_scenario::take_shared<IncentiveFundsPool<USDC_TEST>>(scenario);
            let usdc_coin = coin::mint_for_testing<USDC_TEST>(100000_000000, test_scenario::ctx(scenario));
            incentive_v2::add_funds(&owner_cap, &mut usdc_funds, usdc_coin, 100000_000000, test_scenario::ctx(scenario));
            let usdc_before = incentive_v2::get_funds_value(&usdc_funds);
            assert!(usdc_before == 100000_000000, 0);

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_shared(usdc_funds);
            test_scenario::return_to_sender(scenario, owner_cap);
        };
    }

    #[test_only]
    public fun create_incentive_pool_for_testing<T>(
        scenario: &mut Scenario,
        funds_pool: &IncentiveFundsPool<T>,
        phase: u64,
        start_at: u64,
        end_at: u64,
        closed_at: u64,
        total_supply: u64,
        option: u8,
        asset_id: u8,
        factor: u256,
    ) {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);
            let incentive = test_scenario::take_shared<Incentive>(scenario);

            // start_at < end_at
            incentive_v2::create_incentive_pool<T>(
                &owner_cap,
                &mut incentive,
                funds_pool,
                phase, // phase
                start_at, // start_at
                end_at, // end_at
                closed_at, // closed_at
                total_supply, // total_supply
                option, // option
                asset_id, // asset_id
                factor, // factor
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(incentive);
            test_scenario::return_to_sender(scenario, owner_cap);
    }

    #[test_only]
    public fun entry_deposit_for_testing<T>(scenario: &mut Scenario, clock: &Clock, pool: &mut Pool<T>, deposit_coin: Coin<T>, asset: u8, amount: u64) {
        let storage = test_scenario::take_shared<Storage>(scenario);
        let incentive = test_scenario::take_shared<Incentive>(scenario);
        let incentive_v3 = test_scenario::take_shared<IncentiveV3>(scenario);
        
        incentive_v3::entry_deposit(clock, &mut storage, pool, asset, deposit_coin, amount, &mut incentive, &mut incentive_v3, test_scenario::ctx(scenario));

        test_scenario::return_shared(storage);
        test_scenario::return_shared(incentive);
        test_scenario::return_shared(incentive_v3);
    }

    #[test_only]
    public fun entry_liquidation_for_testing<T>(scenario: &mut Scenario, clock: &Clock, debt_asset: u8, debt_pool: &mut Pool<T>, debt_coin: Coin<T>, collateral_asset: u8, collateral_pool: &mut Pool<T>, liquidate_user: address, liquidate_amount: u64) {
        let storage = test_scenario::take_shared<Storage>(scenario);
        let incentive = test_scenario::take_shared<Incentive>(scenario);
        let incentive_v3 = test_scenario::take_shared<IncentiveV3>(scenario);
        let price_oracle = test_scenario::take_shared<PriceOracle>(scenario);

        incentive_v3::entry_liquidation(clock, &price_oracle, &mut storage, debt_asset, debt_pool, debt_coin, collateral_asset, collateral_pool, liquidate_user, liquidate_amount, &mut incentive, &mut incentive_v3, test_scenario::ctx(scenario));

        test_scenario::return_shared(storage);
        test_scenario::return_shared(incentive);
        test_scenario::return_shared(incentive_v3);
        test_scenario::return_shared(price_oracle);
    }

    #[test_only]
    public fun entry_borrow_for_testing<T>(scenario: &mut Scenario, clock: &Clock, pool: &mut Pool<T>, asset: u8, amount: u64) {
        let storage = test_scenario::take_shared<Storage>(scenario);
        let incentive = test_scenario::take_shared<Incentive>(scenario);
        let incentive_v3 = test_scenario::take_shared<IncentiveV3>(scenario);
        let price_oracle = test_scenario::take_shared<PriceOracle>(scenario);
        
        incentive_v3::entry_borrow(clock, &price_oracle, &mut storage, pool, asset, amount, &mut incentive, &mut incentive_v3, test_scenario::ctx(scenario));

        test_scenario::return_shared(storage);
        test_scenario::return_shared(incentive);
        test_scenario::return_shared(incentive_v3);
        test_scenario::return_shared(price_oracle);
    }

    #[test_only]
    public fun entry_repay_for_testing<T>(scenario: &mut Scenario, clock: &Clock, pool: &mut Pool<T>, asset: u8, amount: u64, repay_coin: Coin<T>) {
        let storage = test_scenario::take_shared<Storage>(scenario);
        let incentive = test_scenario::take_shared<Incentive>(scenario);
        let incentive_v3 = test_scenario::take_shared<IncentiveV3>(scenario);
        let price_oracle = test_scenario::take_shared<PriceOracle>(scenario);
        
        incentive_v3::entry_repay(clock, &price_oracle, &mut storage, pool, asset, repay_coin, amount, &mut incentive, &mut incentive_v3, test_scenario::ctx(scenario));

        test_scenario::return_shared(storage);
        test_scenario::return_shared(incentive);
        test_scenario::return_shared(incentive_v3);
        test_scenario::return_shared(price_oracle);
    }

    #[test_only]
    public fun claim_reward_for_testing<T>(scenario: &mut Scenario, clock: &Clock, funds_pool: &mut IncentiveFundsPool<T>, asset: u8, option: u8) {
        let storage = test_scenario::take_shared<Storage>(scenario);
        let incentive = test_scenario::take_shared<Incentive>(scenario);
        let price_oracle = test_scenario::take_shared<PriceOracle>(scenario);
        
        incentive_v2::claim_reward(clock, &mut incentive, funds_pool, &mut storage, asset, option, test_scenario::ctx(scenario));

        test_scenario::return_shared(storage);
        test_scenario::return_shared(incentive);
        test_scenario::return_shared(price_oracle);
    }

    //Should entry_deposit successfully handle a deposit action, updating rewards and executing the deposit action
    #[test]
    public fun test_deposit() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            create_incentive_pool_for_testing(
                &mut scenario,
                &usdt_funds,
                0, // phase
                current_timestamp, // start, 2023-11-15 08:00:00
                current_timestamp + 1000 * 60 * 60, // end, 2023-11-15 09:00:00
                0, // closed
                100_000000, // total_supply
                1, // option 
                0, // asset
                1000000000000000000000000000 // factor
            );

            test_scenario::return_shared(usdt_funds);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 10 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);

            let coin = coin::mint_for_testing<USDC_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 1, 100_000000000);
            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_deposit fail when provided with a null or invalid TxContext
    #[test]
    #[expected_failure(abort_code = 46001, location=utils::utils)]
    public fun test_fail_entry_deposit() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            create_incentive_pool_for_testing(
                &mut scenario,
                &usdt_funds,
                0, // phase
                current_timestamp, // start, 2023-11-15 08:00:00
                current_timestamp + 1000 * 60 * 60, // end, 2023-11-15 09:00:00
                0, // closed
                100_000000, // total_supply
                1, // option 
                0, // asset
                1000000000000000000000000000 // factor
            );

            test_scenario::return_shared(usdt_funds);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 10 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);

            let coin = coin::mint_for_testing<USDC_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 1, 1000_000000000);
            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 1000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_withdraw successfully handle a withdrawal action, updating rewards and executing the withdrawal
    #[test]
    public fun test_withdraw_funds() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            incentive_v2::withdraw_funds(&owner_cap, &mut usdt_funds, 100000_000000, test_scenario::ctx(&mut scenario));
            let after = incentive_v2::get_funds_value(&usdt_funds);
            assert!(after == 100000_000000 - 100000_000000, 0); // No.2 can withdraw funds

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_withdraw fail when the withdrawal amount exceeds the user's balance
    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::incentive_v2)]
    public fun test_fail_withdraw_inefficient_fund() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            incentive_v2::withdraw_funds(&owner_cap, &mut usdt_funds, 1000000_000000, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should Fail if users try to withdraw more than once
    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::incentive_v2)]
    public fun test_fail_withdraw_funds_twice() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            incentive_v2::withdraw_funds(&owner_cap, &mut usdt_funds, 100000_000000, test_scenario::ctx(&mut scenario));
            let after = incentive_v2::get_funds_value(&usdt_funds);
            assert!(after == 100000_000000 - 100000_000000, 0); // No.2 can withdraw funds

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            incentive_v2::withdraw_funds(&owner_cap, &mut usdt_funds, 1, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_borrow successfully handle a borrow action, updating rewards and executing the borrow
    #[test]
    public fun test_borrow() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        //Deposit First then can borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 7000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        //Try to borrow again
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 2000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 5000_000000000, 0);

            test_scenario::return_shared(pool);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_borrow fail when the borrow amount exceeds the user's credit limit
    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::validation)]
    public fun test_fail_borrow_exceed_credit() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        //Deposit First then can borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_repay successfully handle a repay action, updating rewards and executing the repay
    #[test]
    public fun test_repay() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        //Deposit First then can borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(11000_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 7000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        //repay
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));


            entry_repay_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000, coin);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_repay fail when the repay token is not the same as the borrowed token
    #[test]
    #[expected_failure(abort_code = 1505, location=lending_core::validation)]
    public fun test_fail_repay_another_token() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        //Deposit First then can borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 7000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        //repay
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 1000);
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let coin = coin::mint_for_testing<USDT_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));


            entry_repay_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000, coin);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should entry_repay fail when the repay amount is more than the user's debt
    #[test]
    #[expected_failure(abort_code = 0, location=lending_core::incentive_v2_more)]
    public fun test_fail_repay_more_than_debt() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        //Deposit First then can borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 40 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 7000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        //repay
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 1000);
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));


            entry_repay_for_testing(&mut scenario, &_clock, &mut pool, 0, 6000_000000000, coin);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should create_incentive_pool successfully create an incentive pool with valid parameters
    #[test]
    public fun test_create_pool() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            create_incentive_pool_for_testing(
                &mut scenario,
                &usdt_funds,
                0, // phase
                current_timestamp, // start, 2023-11-15 08:00:00
                current_timestamp + 1000 * 60 * 60, // end, 2023-11-15 09:00:00
                0, // closed
                100_000000, // total_supply
                1, // option 
                0, // asset
                1000000000000000000000000000 // factor
            );

            test_scenario::return_shared(usdt_funds);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);

    }

    //Should create_incentive_pool fail when provided with invalid duration (start_at >= end_at)
    #[test]
    #[expected_failure(abort_code = 1802, location=lending_core::incentive_v2)]
    public fun test_fail_create_pool() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            create_incentive_pool_for_testing(
                &mut scenario,
                &usdt_funds,
                0, // phase
                current_timestamp, // start, 2023-11-15 08:00:00
                current_timestamp - 1000 * 60 * 60, // end, 2023-11-15 09:00:00
                0, // closed
                100_000000, // total_supply
                1, // option 
                0, // asset
                1000000000000000000000000000 // factor
            );

            test_scenario::return_shared(usdt_funds);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);

    }

    //Should create_funds_pool successfully create a funds pool with valid parameters
    #[test]
    public fun test_create_fund_pool() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }


    #[test_only]
    public fun initial_incentive_v2_double_pool(scenario: &mut Scenario) {
        // create incentive owner cap
        test_scenario::next_tx(scenario, OWNER);
        {
            let storage_owner_cap = test_scenario::take_from_sender<StorageOwnerCap>(scenario);
            incentive_v2::create_and_transfer_owner(&storage_owner_cap, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, storage_owner_cap);
        };
        
        // create incentive
        test_scenario::next_tx(scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);
            incentive_v2::create_incentive(&owner_cap, test_scenario::ctx(scenario));
            test_scenario::return_to_sender(scenario, owner_cap);
        };

        // create funds pool
        test_scenario::next_tx(scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);
            let incentive = test_scenario::take_shared<Incentive>(scenario);
            incentive_v2::create_funds_pool<USDC_TEST>(&owner_cap, &mut incentive, 1, false, test_scenario::ctx(scenario));
            incentive_v2::create_funds_pool<USDT_TEST>(&owner_cap, &mut incentive, 2, false, test_scenario::ctx(scenario));
            
            // should fail when try to create funds pool with an existing ID
            incentive_v2::create_funds_pool<USDC_TEST>(&owner_cap, &mut incentive, 2, true, test_scenario::ctx(scenario));

            test_scenario::return_shared(incentive);
            test_scenario::return_to_sender(scenario, owner_cap);
        };
        

        // increase USDC pool funds
        // increase USDT pool funds
        test_scenario::next_tx(scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(scenario);

            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(scenario);
            let coin = coin::mint_for_testing<USDT_TEST>(100000_000000, test_scenario::ctx(scenario));
            incentive_v2::add_funds(&owner_cap, &mut usdt_funds, coin, 0, test_scenario::ctx(scenario));
            let usdt_before = incentive_v2::get_funds_value(&usdt_funds);
            assert!(usdt_before == 100000_000000, 0);

            let usdc_funds = test_scenario::take_shared<IncentiveFundsPool<USDC_TEST>>(scenario);
            let usdc_coin = coin::mint_for_testing<USDC_TEST>(100000_000000, test_scenario::ctx(scenario));
            incentive_v2::add_funds(&owner_cap, &mut usdc_funds, usdc_coin, 0, test_scenario::ctx(scenario));
            let usdc_before = incentive_v2::get_funds_value(&usdc_funds);
            assert!(usdc_before == 100000_000000, 0);

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_shared(usdc_funds);
            test_scenario::return_to_sender(scenario, owner_cap);
        };
    }

    //Should create_funds_pool fail when attempting to create with an existing ID (force not true)
    #[test]
    #[expected_failure(abort_code = 46000, location=utils::utils)]
    public fun test_fail_create_fund_pool() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);

            initial_incentive_v2_double_pool(&mut scenario);
        };



        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should add_funds successfully add funds to an incentive funds pool
    #[test]
    public fun test_add_fund_to_pool() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should add_funds fail when the funds to be added exceed the maximum allowed balance
    #[test]
    #[expected_failure(abort_code = 46000, location=utils::utils)]
    public fun test_fail_add_fund_pool() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        let current_timestamp = 1700006400000;
        clock::set_for_testing(&mut _clock, current_timestamp);
        {
            base::initial_protocol(&mut scenario, &_clock);

            initial_incentive_v2_double_pool(&mut scenario);
        };


        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should withdraw_funds successfully withdraw funds from an incentive funds pool
    #[test]
    public fun test_withdraw() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            incentive_v2::withdraw_funds(&owner_cap, &mut usdt_funds, 100000_000000, test_scenario::ctx(&mut scenario));
            let after = incentive_v2::get_funds_value(&usdt_funds);
            assert!(after == 100000_000000 - 100000_000000, 0); // No.2 can withdraw funds

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should withdraw_funds fail when the withdrawal amount exceeds the available balance
    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::incentive_v2)]
    public fun test_fail_withdraw() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let owner_cap = test_scenario::take_from_sender<OwnerCap>(&scenario);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            incentive_v2::withdraw_funds(&owner_cap, &mut usdt_funds, 200000_000000, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(usdt_funds);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should claim_reward successfully claim rewards for eligible users
    #[test]
    public fun test_claim_reward() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        //Deposit First then can borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let coin = coin::mint_for_testing<SUI_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));

            entry_deposit_for_testing(&mut scenario, &_clock, &mut pool, coin, 0, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10);
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            entry_borrow_for_testing(&mut scenario, &_clock, &mut pool, 0, 3000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 7000_000000000, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10);
            let usdt_funds = test_scenario::take_shared<IncentiveFundsPool<USDT_TEST>>(&scenario);

            claim_reward_for_testing(&mut scenario, &_clock, &mut usdt_funds, 0, 1);

            test_scenario::return_shared(usdt_funds);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    //Should version_verification verify the correct version of an incentive																												
    #[test]
    public fun test_version_verification() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            clock::increment_for_testing(&mut _clock, 1000 * 10); // 20 seconds after the reward starts
            let incentive = test_scenario::take_shared<Incentive>(&scenario);


            incentive_v2::version_verification(&incentive);


            test_scenario::return_shared(incentive);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }


}