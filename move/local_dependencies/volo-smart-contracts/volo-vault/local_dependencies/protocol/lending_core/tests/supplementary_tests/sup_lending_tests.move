#[test_only]
module lending_core::sup_lending_tests {
    use sui::clock;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self, Scenario};

    use math::ray_math;
    use oracle::oracle::{Self, PriceOracle, OracleFeederCap};
    use lending_core::base;
    use lending_core::logic::{Self};
    use lending_core::pool::{Self, Pool};
    use lending_core::sui_test::{SUI_TEST};
    use lending_core::usdt_test::{USDT_TEST};
    use lending_core::usdc_test::{USDC_TEST};
    use lending_core::navx_test::{NAVX_TEST};
    use lending_core::incentive_v2::{Self, OwnerCap, Incentive, IncentiveFundsPool};
    use lending_core::incentive_v3::{Self, Incentive as IncentiveV3};

    use utils::utils;
    use sui::transfer;

    use lending_core::lib;

    use lending_core::base_lending_tests::{Self};
    use lending_core::storage::{Self, Storage, OwnerCap as StorageOwnerCap};
    use lending_core::sup_global;

    const OWNER: address = @0xA;
    
    #[test_only]
    // init func to test lending through incentivev2 
    public fun initial_incentive_v2_v3(scenario: &mut Scenario) {

        test_scenario::next_tx(scenario, OWNER);
        {  
            incentive_v3::init_for_testing(test_scenario::ctx(scenario));
        };
        
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

    #[test]
    // Should liquidate successfully and transfer bonus and deposit treasury
    // Should liquidator perform liquidation and user pay bonus and reduce debt
    public fun test_entry_liquidation_call() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);

        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(1000_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 1000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            // deposit 1000 SUI(500U), borrow 250U
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 250_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update SUI price to 0.3, (60%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                0,                 // Oracle id
                300000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                0,
                &mut sui_pool,
                userB,
                10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            // assert!(coin::value(&usdt_balance) == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };
        
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));
            let avg_ltv = logic::calculate_avg_ltv(&clock, &price_oracle, &mut storage, userB);
            let avg_threshold = logic::calculate_avg_threshold(&clock, &price_oracle, &mut storage, userB);
            let health_factor_in_borrow = ray_math::ray_div(avg_threshold, avg_ltv);
            std::debug::print(&health_factor_in_borrow); // 1272727272727272727272727273

            // 0.3 * 1000 - 0.9999 * (10 - 10 * 10%) = 289.011
            std::debug::print(&logic::user_collateral_value(&clock, &price_oracle, &mut storage, 0, userB)); //289001100000
            // 0.9999 * (250 - 10) = 239.976
            std::debug::print(&logic::user_loan_value(&clock, &price_oracle, &mut storage, 2, userB)); // 239976000000
            // 289 * 0.7 / 239 ~= 0.84
            std::debug::print(&logic::user_health_factor(&clock, &mut storage, &price_oracle, userB)); // 843004175417541754175417542

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // let usdt_balance = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario); // fixed: full repay and bonus are reflected in collateral assets
            let sui_balance = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let (_, treasury_balance_value, _) = pool::get_pool_info(&pool);

            lib::printf(b"liquidator balance after");
            // 1000000  = 1U (bonus)
            // std::debug::print(&coin::value(&usdt_balance)); // fixed: bonus are reflected in collateral assets

            // 32_996700000 =9.89901U = 10U - 0.1U(tresury) // fixed: needs to add bonus
            // 36329700000 = 10u * 35% = 3.5u
            // collateral amount = 10u / 0.3SuiPrice = 33.33Sui
            // bonus = (33.33 * 10%) * (1 - 10%) = 2.9997Sui
            std::debug::print(&coin::value(&sui_balance)); // 36329700000
            // 333300000 ~= 0.1U
            std::debug::print(&treasury_balance_value);

            // assert!(coin::value(&usdt_balance) == 1_000000, 0); // fixed: bonus are reflected in collateral assets
            assert!(coin::value(&sui_balance) == 36329700000, 0); // (33.33 + 2.9997) * 1e9 = 36329699999
            assert!(treasury_balance_value == 333300000, 0);
            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, sui_balance);
            // test_scenario::return_to_sender(&scenario, usdt_balance); // fixed: bonus are reflected in collateral assets
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    // Should liquidate successfully and transfer bonus and deposit treasury for non_entry
    public fun test_entry_liquidation_call_non_entry() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);

        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(1000_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 1000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            // deposit 1000 SUI(500U), borrow 250U
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 250_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update SUI price to 0.3, (60%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                0,                 // Oracle id
                300000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));
            let debt_balance =  utils::split_coin_to_balance(usdt_coin, 10_000000, test_scenario::ctx(&mut scenario));

            let (collecteral, debt) = incentive_v3::liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                debt_balance,
                0,
                &mut sui_pool,
                userB,
                // 10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            if (sui::balance::value(&collecteral) > 0) {
                let _coin = coin::from_balance(collecteral, test_scenario::ctx(&mut scenario));
                transfer::public_transfer(_coin, OWNER);
            } else {
                sui::balance::destroy_zero(collecteral)
            };

            if (sui::balance::value(&debt) > 0) {
                let _coin = coin::from_balance(debt, test_scenario::ctx(&mut scenario));
                transfer::public_transfer(_coin, OWNER);
            } else {
                sui::balance::destroy_zero(debt)
            };

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };
        
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));
            let avg_ltv = logic::calculate_avg_ltv(&clock, &price_oracle, &mut storage, userB);
            let avg_threshold = logic::calculate_avg_threshold(&clock, &price_oracle, &mut storage, userB);
            let health_factor_in_borrow = ray_math::ray_div(avg_threshold, avg_ltv);
            std::debug::print(&health_factor_in_borrow); // 1272727272727272727272727273

            // 0.3 * 1000 - 0.9999 * (10 - 10 * 10%) = 289.011
            std::debug::print(&logic::user_collateral_value(&clock, &price_oracle, &mut storage, 0, userB)); //289001100000
            // 0.9999 * (250 - 10) = 239.976
            std::debug::print(&logic::user_loan_value(&clock, &price_oracle, &mut storage, 2, userB)); // 239976000000
            // 289 * 0.7 / 239 ~= 0.84
            std::debug::print(&logic::user_health_factor(&clock, &mut storage, &price_oracle, userB)); // 843004175417541754175417542

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // let usdt_balance = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario); // fixed: full repay and bonus are reflected in collateral assets
            let sui_balance = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let (_, treasury_balance_value, _) = pool::get_pool_info(&pool);

            lib::printf(b"liquidator balance after");
            // 1000000  = 1U (bonus)
            // std::debug::print(&coin::value(&usdt_balance)); // fixed: bonus are reflected in collateral assets

            // 32_996700000 =9.89901U = 10U - 0.1U(tresury) // fixed: needs to add bonus
            // 36329700000 = 10u * 35% = 3.5u
            // collateral amount = 10u / 0.3SuiPrice = 33.33Sui
            // bonus = (33.33 * 10%) * (1 - 10%) = 2.9997Sui
            std::debug::print(&coin::value(&sui_balance)); // 36329700000
            // 333300000 ~= 0.1U
            std::debug::print(&treasury_balance_value);

            // assert!(coin::value(&usdt_balance) == 1_000000, 0); // fixed: bonus are reflected in collateral assets
            assert!(coin::value(&sui_balance) == 36329700000, 0); // (33.33 + 2.9997) * 1e9 = 36329699999
            assert!(treasury_balance_value == 333300000, 0);

            let has_usdt_balance = test_scenario::has_most_recent_for_sender<Coin<USDT_TEST>>(&scenario);
            assert!(!has_usdt_balance, 0);

            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, sui_balance);
            // test_scenario::return_to_sender(&scenario, usdt_balance); // fixed: bonus are reflected in collateral assets
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    // Should transfer balance back if amount excess 
    public fun test_entry_liquidation_call_excess() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);
        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(1000_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 1000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            // deposit 1000 SUI(500U), borrow 250U
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 250_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update SUI price to 0.3, (60%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                0,                 // Oracle id
                300000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);

            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10000_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                0,
                &mut sui_pool,
                userB,
                10000_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));


            // assert!(coin::value(&usdt_balance) == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_balance = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            let sui_balance = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let (_, treasury_balance_value, _) = pool::get_pool_info(&pool);

            lib::printf(b"liquidator balance after");
            // liquidable collateral = 1000Sui * 0.3SuiPrice * 35% = 105U = 105u / 0.3SuiPrice = 350Sui
            // liquidable debt = 105U
            // bonus = (105 * 10%) * (1 - 10%) = 9.45u / 0.3 = 31.5Sui

            // (10000USDT * 0.9999USDTPrice) - 105 = 9894u / 0.9999 = 9894.989498949895
            std::debug::print(&coin::value(&usdt_balance));
            // 350Sui + 31.5Sui = 381.5
            std::debug::print(&coin::value(&sui_balance)); // 
            // 3500000000
            std::debug::print(&treasury_balance_value);

            assert!(coin::value(&usdt_balance) == 9894989498, 0); // 9894.989498949895 * 1e6 = 9894989498
            assert!(coin::value(&sui_balance) == 381500000000, 0); // 381.5 * 1e9
            assert!(treasury_balance_value == 3500000000, 0);
            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, sui_balance);
            test_scenario::return_to_sender(&scenario, usdt_balance);
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    // Should liquidate successfully for asset with 6 decimals
    public fun test_entry_liquidation_call_excess_6_decimals() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);
        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit USDC 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDC_TEST>(1000_000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 1, 1000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT 500
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 500_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update USDT price to 4 (400%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                2,                 // Oracle id
                4_000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);

            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(500_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                1,
                &mut usdc_pool,
                userB,
                500_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(usdc_pool);
            test_scenario::return_shared(incentive);
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_balance = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario);
            let usdc_balance = test_scenario::take_from_sender<Coin<USDC_TEST>>(&scenario);

            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);

            let (_, treasury_balance_value, _) = pool::get_pool_info(&usdc_pool);

            lib::printf(b"liquidator balance after");
            // liquidable collateral = 1000 * 0.35 = 350USDC
            // liquidable debt = 350 / 4 = 87.5USDT
            // bonus = (350 * 5%) * (1 - 10%) = 15.75USDC

            std::debug::print(&coin::value(&usdc_balance)); 
            std::debug::print(&coin::value(&usdt_balance));
            std::debug::print(&treasury_balance_value);

            // 350 + 15.75 
            assert!(coin::value(&usdc_balance) == 365_750000, 0); 
            // 500 - 87.5 = 422.5
            assert!(coin::value(&usdt_balance) == 412_500000, 0);
            // (350 * 5%) * (10%) 
            assert!(treasury_balance_value == 1_750000, 0);

            test_scenario::return_shared(usdc_pool);
            test_scenario::return_shared(usdt_pool);
            test_scenario::return_to_sender(&scenario, usdc_balance);
            test_scenario::return_to_sender(&scenario, usdt_balance);
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    // Should liquidate multiple times for a user with multiple collterals and debts
    public fun test_entry_liquidation_multi_assests_and_debts() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);

        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 800 (400U)
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(800_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 800_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit USDC 100
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDC_TEST>(100_000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 1, 100_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT 200
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 200_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDC 50
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 1, 50_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update SUI price to 0.25, (50%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                0,                 // Oracle id
                250000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation: collecteral sui, debt usdc, amount 10 
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            let usdc_coin = coin::mint_for_testing<USDC_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                1,
                &mut usdc_pool,
                usdc_coin,
                0,
                &mut sui_pool,
                userB,
                10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdc_pool);
            test_scenario::return_shared(sui_pool);
        };
        
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));
            let avg_ltv = logic::calculate_avg_ltv(&clock, &price_oracle, &mut storage, userB);
            let avg_threshold = logic::calculate_avg_threshold(&clock, &price_oracle, &mut storage, userB);
            let health_factor_in_borrow = ray_math::ray_div(avg_threshold, avg_ltv);
            lib::printf(b"liquidation1");
            std::debug::print(&health_factor_in_borrow); // 1325404086611771881671241233

            // 200 - 10 * (10% + 1%) = 189
            std::debug::print(&logic::user_collateral_value(&clock, &price_oracle, &mut storage, 0, userB)); //189000000000
            // 1 * (50 - 10) = 40
            std::debug::print(&logic::user_loan_value(&clock, &price_oracle, &mut storage, 1, userB)); // 40000000000
            //  (189 * 0.7 + 100 * 0.85) / (40 + 200)  ~= 0.905 
            std::debug::print(&logic::user_health_factor(&clock, &mut storage, &price_oracle, userB)); // 905492124343695307942328527

            assert!(logic::user_collateral_value(&clock, &price_oracle, &mut storage, 0, userB) == 189000000000, 0);
            assert!(logic::user_loan_value(&clock, &price_oracle, &mut storage, 1, userB) == 40000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
        };


        // liquidation: collecteral sui, debt usdt, amount 10 
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);

            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                0,
                &mut sui_pool,
                userB,
                10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
            test_scenario::return_shared(sui_pool);
        };
        
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));
            lib::printf(b"liquidation2");

            // 189 - 10 * (10% + 1%) * 0.9999 ~= 178
            std::debug::print(&logic::user_collateral_value(&clock, &price_oracle, &mut storage, 0, userB)); //178001100000
            // 0.9999 * (200 - 10) ~= 190
            std::debug::print(&logic::user_loan_value(&clock, &price_oracle, &mut storage, 2, userB)); // 189981000000
            //  178 * 0.7 + 100 * 0.85 / 40 + 190 ~= 0.911
            std::debug::print(&logic::user_health_factor(&clock, &mut storage, &price_oracle, userB)); // 911382983811706184423930673

            // assert!(logic::user_collateral_value(&clock, &price_oracle, &mut storage, 0, userB) == 189000000000, 0);
            // assert!(logic::user_loan_value(&clock, &price_oracle, &mut storage, 1, userB) == 40000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let sui_balance = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);
            let sui_balance2 = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);

            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let (_, treasury_balance_value, _) = pool::get_pool_info(&pool);

            lib::printf(b"liquidator balance after");
            // (10USDC + 10 USDC) * (1 + (10 - 1)%) / 0.25 = 87.19564
            std::debug::print(&(coin::value(&sui_balance) + coin::value(&sui_balance2))); // 87195640000 
            // (10USDC + 10 USDC) * 1% / 0.25 = 0.79996
            std::debug::print(&treasury_balance_value); // 799960000

            assert!(coin::value(&sui_balance) + coin::value(&sui_balance2) == 87195640000, 0);
            assert!(treasury_balance_value == 799960000, 0);
            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, sui_balance);
            test_scenario::return_to_sender(&scenario, sui_balance2);
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    //Should liquidation bonus and bonus to treasury changed after setting new factors 
    public fun test_entry_liquidation_factor_changed() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);

        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(1000_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 1000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            // deposit 1000 SUI(500U), borrow 250U
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 250_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update SUI price to 0.3, (60%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                0,                 // Oracle id
                300000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));


            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                0,
                &mut sui_pool,
                userB,
                10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            // assert!(coin::value(&usdt_balance) == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };

        // oracle: update SUI price to 0.3, (60%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<StorageOwnerCap>(&scenario);            

            storage::set_treasury_factor(&owner_cap,&mut storage, 0, 200000000000000000000000000);

            test_scenario::return_to_sender(&scenario, owner_cap);
            test_scenario::return_shared(storage);
        };
        
        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));


            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                0,
                &mut sui_pool,
                userB,
                10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            // assert!(coin::value(&usdt_balance) == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };


        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // let usdt_balance = test_scenario::take_from_sender<Coin<USDT_TEST>>(&scenario); // fixed: full repay and bonus are reflected in collateral assets
            let sui_balance = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);
            let sui_balance2 = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);

            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let (_, treasury_balance_value, _) = pool::get_pool_info(&pool);

            lib::printf(b"liquidator balance after");

            // 0.9999 * (1 + 0.1 - 0.01) / 0.3 + 0.9999 * (1 + 0.1 - 0.02) / 0.3 = 72.3261
            std::debug::print(&(coin::value(&sui_balance) + coin::value(&sui_balance2))); 

            // 0.9999 * (0.01) / 0.3 + 0.9999 * (0.02) / 0.3 = 0.9999
            std::debug::print(&treasury_balance_value);

            assert!(coin::value(&sui_balance) + coin::value(&sui_balance2)== 72326100000, 0);
            assert!(treasury_balance_value == 999900000, 0);
            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, sui_balance);
            test_scenario::return_to_sender(&scenario, sui_balance2);
            // test_scenario::return_to_sender(&scenario, usdt_balance); // fixed: bonus are reflected in collateral assets
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    #[expected_failure(abort_code = 1606, location=lending_core::logic)]
    // Should fail if h_f > 1
    public fun test_entry_liquidation_call_fails_if_healthy() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);

        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(1000_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 1000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            // deposit 1000 SUI(500U), borrow 250U
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 250_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                2,
                &mut usdt_pool,
                usdt_coin,
                0,
                &mut sui_pool,
                userB,
                10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            // assert!(coin::value(&usdt_balance) == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    // Should fail liquidation_entry for reverse asset input
    #[expected_failure(abort_code = 1602, location=lending_core::logic)]
    public fun test_entry_liquidation_call_fail_for_reverse_asset_input() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);
        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit USDC 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDC_TEST>(1000_000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 1, 1000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT 500
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 500_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update USDT price to 4 (400%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                2,                 // Oracle id
                4_000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);

            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(500_000000, test_scenario::ctx(&mut scenario_liquidator));

            incentive_v3::entry_liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                1,
                &mut usdt_pool,
                usdt_coin,
                2,
                &mut usdc_pool,
                userB,
                500_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(usdc_pool);
            test_scenario::return_shared(incentive);
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test]
    // Should fail liquidation_non_entry for reverse asset input
    #[expected_failure(abort_code = 1602, location=lending_core::logic)]
    public fun test_non_entry_liquidation_call_fail_for_reverse_asset_input() {
        let userA = @0xA;
        let userB = @0xB;
        let liquidator = @0xC;
        let scenarioA = test_scenario::begin(userA);
        let scenarioB = test_scenario::begin(userB);
        let scenario_liquidator = test_scenario::begin(liquidator);

        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
            initial_incentive_v2_v3(&mut scenario);

        };

        // lending: userA deposit USDT 1000000
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<USDT_TEST>(1000000_000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 2, 1000000_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB deposit SUI 1000
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(1000_000000000, test_scenario::ctx(&mut scenarioB));

            base_lending_tests::base_deposit_for_testing(&mut scenarioB, &clock, &mut pool, coin, 0, 1000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // lending: userB borrow USDT
        test_scenario::next_tx(&mut scenarioB, userB);
        {
            let pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            // deposit 1000 SUI(500U), borrow 250U
            base_lending_tests::base_borrow_for_testing(&mut scenarioB, &clock, &mut pool, 2, 250_000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // oracle: update SUI price to 0.3, (60%)
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenarioB));

            oracle::update_token_price(
                &oracle_feeder_cap, // feeder cap
                &clock,
                &mut price_oracle, // PriceOracle
                0,                 // Oracle id
                300000000,    // price
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_shared(storage);
        };

        // liquidation call
        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let storage = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let incentive = test_scenario::take_shared<Incentive>(&scenario);
            let incentive_v3 = test_scenario::take_shared<IncentiveV3>(&scenario);
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(10_000000, test_scenario::ctx(&mut scenario_liquidator));
            let debt_balance =  utils::split_coin_to_balance(usdt_coin, 10_000000, test_scenario::ctx(&mut scenario));

            let (collecteral, debt) = incentive_v3::liquidation(
                &clock,
                &price_oracle,
                &mut storage,
                0,
                &mut usdt_pool,
                debt_balance,
                2,
                &mut sui_pool,
                userB,
                // 10_000000,
                &mut incentive,
                &mut incentive_v3,
                test_scenario::ctx(&mut scenario));

            if (sui::balance::value(&collecteral) > 0) {
                let _coin = coin::from_balance(collecteral, test_scenario::ctx(&mut scenario));
                transfer::public_transfer(_coin, OWNER);
            } else {
                sui::balance::destroy_zero(collecteral)
            };

            if (sui::balance::value(&debt) > 0) {
                let _coin = coin::from_balance(debt, test_scenario::ctx(&mut scenario));
                transfer::public_transfer(_coin, OWNER);
            } else {
                sui::balance::destroy_zero(debt)
            };

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(incentive);                                                                                                                                                                                        
            test_scenario::return_shared(incentive_v3);
            test_scenario::return_shared(usdt_pool);
        };

        test_scenario::end(scenario);
        test_scenario::end(scenarioA);
        test_scenario::end(scenarioB);
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario_liquidator);
    }

    #[test] 
    // Should withdraw user's max balance from pool for excess input amount
    public fun test_withdraw_max() {
        let userA = @0xAC;
        let scenario = test_scenario::begin(OWNER);
        let scenarioA = test_scenario::begin(userA);

        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        
        {
            base::initial_protocol(&mut scenario, &_clock);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // deposit more to avoid balance error         
        test_scenario::next_tx(&mut scenarioA, userA);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenarioA));

            base_lending_tests::base_deposit_for_testing(&mut scenarioA, &clock, &mut pool, coin, 0, 100_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);

        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            base_lending_tests::base_withdraw_for_testing(&mut scenario, &clock, &mut pool, 0, 101_000000000);

            // validation
            let (total_supply, _, _) = pool::get_pool_info<SUI_TEST>(&pool);
            lib::print(&total_supply);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let sui_balance = test_scenario::take_from_sender<Coin<SUI_TEST>>(&scenario);
            assert!(coin::value(&sui_balance)  == 100_000000000, 2);
            test_scenario::return_to_sender(&scenario, sui_balance);
        };
        
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenarioA);
        test_scenario::end(scenario);
    }


    #[test] 
    #[expected_failure]
    // Should borrow failed for excess max borrow amount 
    public fun test_borrow_excess() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 0, 101_000000000);
            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 90_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

     #[test] 
     // Should return excess repay amount
    public fun test_repay_excess() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 0, 10_000000000);
            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 90_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_repay_for_testing(&mut scenario, &clock, &mut pool, coin, 0, 100_000000000);
            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test] 
    #[expected_failure(abort_code = 1605, location=lending_core::validation)]
    // Should deposit navx and cannot borrow
    public fun test_deposit_navx_cannot_borrow() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            sup_global::init_protocol(&mut scenario);
        };

        // supply
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<NAVX_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<NAVX_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 5, 100_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        // borrow will fail
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<NAVX_TEST>>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 5, 1);
            
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test] 
    // Should deposit navx and borrow other asset
    public fun test_deposit_navx_cannot_borrow_with_other_asests() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            sup_global::init_protocol(&mut scenario);
        };

        // supply navx
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<NAVX_TEST>>(&scenario);

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<NAVX_TEST>(1000000_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 5, 1000000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 1000000_000000000, 0);

            clock::destroy_for_testing(clock);

            test_scenario::return_shared(pool);
        };

        // supply usdt
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(100_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut usdt_pool, usdt_coin, 0, 100_000000000);


            let (total_supply, _, _) = pool::get_pool_info(&usdt_pool);
            assert!(total_supply == 100_000000000, 0);

            clock::destroy_for_testing(clock);

            test_scenario::return_shared(usdt_pool);

            // coin::burn_for_testing(usdt_coin);
        };

        // borrow
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut usdt_pool, 0, 90_000000000);
            
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(usdt_pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test] 
    // Should run normally if config updated
    public fun test_navx_functions_if_update_config() {
        let scenario = test_scenario::begin(OWNER);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            sup_global::init_protocol(&mut scenario);
        };

        // supply navx
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<NAVX_TEST>>(&scenario);

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let coin = coin::mint_for_testing<NAVX_TEST>(10000_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut pool, coin, 5, 10000_000000000);

            let (total_supply, _, _) = pool::get_pool_info(&pool);
            assert!(total_supply == 10000_000000000, 0);

            clock::destroy_for_testing(clock);

            test_scenario::return_shared(pool);
        };

        // supply usdt
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);

            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let usdt_coin = coin::mint_for_testing<USDT_TEST>(150_000000000, test_scenario::ctx(&mut scenario));

            base_lending_tests::base_deposit_for_testing(&mut scenario, &clock, &mut usdt_pool, usdt_coin, 0, 150_000000000);


            let (total_supply, _, _) = pool::get_pool_info(&usdt_pool);
            assert!(total_supply == 150_000000000, 0);

            clock::destroy_for_testing(clock);

            test_scenario::return_shared(usdt_pool);

            // coin::burn_for_testing(usdt_coin);
        };

        // set config
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let owner_cap = test_scenario::take_from_sender<StorageOwnerCap>(&scenario);
            storage::set_borrow_cap(&owner_cap,&mut stg, 5, 800000000000000000000000000);

            storage::set_ltv(&owner_cap,&mut stg, 5, 800000000000000000000000000);
            storage::set_liquidation_threshold(&owner_cap,&mut stg, 5, 850000000000000000000000000);
            test_scenario::return_shared(stg);
            test_scenario::return_to_sender(&scenario, owner_cap);
        };

        // borrow usdt
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let usdt_pool = test_scenario::take_shared<Pool<USDT_TEST>>(&scenario);

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut usdt_pool, 0, 100_000000000);
            
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(usdt_pool);
        };

        // borrow navx
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            let pool = test_scenario::take_shared<Pool<NAVX_TEST>>(&scenario);

            base_lending_tests::base_borrow_for_testing(&mut scenario, &clock, &mut pool, 5, 1000_000000000);
            
            clock::destroy_for_testing(clock);
            test_scenario::return_shared( pool);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }
}