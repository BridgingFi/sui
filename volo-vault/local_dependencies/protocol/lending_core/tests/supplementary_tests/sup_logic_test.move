#[test_only]
module lending_core::sup_logic_test {
    use std::vector;
    use sui::clock;
    use sui::test_scenario::{Self};

    use math::ray_math;
    use oracle::oracle::{PriceOracle, OracleFeederCap, OracleAdminCap, Self};
    use lending_core::sup_global;
    use lending_core::sup_edge_global;
    use lending_core::sup_edge_global_2;

    use lending_core::logic::{Self};
    use lending_core::btc_test::{BTC_TEST};
    use lending_core::eth_test::{ETH_TEST};
    use lending_core::eth2_test::{ETH2_TEST};
    use lending_core::usdt_test::{USDT_TEST};
    use lending_core::usdc_test::{USDC_TEST};
    use lending_core::test_coin::{TEST_COIN};
    use lending_core::storage::{Self, Storage};
    use lending_core::lib;
    use lending_core::calculator;

    const OWNER: address = @0xA;

    #[test]
    #[expected_failure(abort_code = 1505, location=lending_core::validation)]
    // Should fail if asset not exist
    public fun test_execute_deposit_assest_invalid() {
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut storage, 1, OWNER, 100);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should succeed with extremely large amount
    // Should set asset to collecteral for first time deposit
    public fun test_execute_deposit_large() {
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let storage = test_scenario::take_shared<Storage>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut storage, 0, OWNER, 2000000000000_000000000);
            
            let (total_supply, _) = storage::get_total_supply(&mut storage, 0);
            assert!(total_supply == 2000000000000_000000000, 0);

            let (collaterals, _) = storage::get_user_assets(&storage, OWNER);
            let collaterals_after = vector::empty<u8>();
            vector::push_back(&mut collaterals_after, 0);
            assert!(collaterals == collaterals_after, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(storage);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::validation)]
    // Should fail for not enough balance 
    public fun test_execute_withdraw_over_balance() {
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, OWNER, 100);

            logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, OWNER, 101);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }


    #[test]
    // Should remove collateral if withdraw full balance
    public fun test_execute_withdraw_full() {
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);


        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let cur_collaterals = vector::empty<u8>();
            vector::push_back(&mut cur_collaterals, 0);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, OWNER, 100);
            let (collaterals_before, _) = storage::get_user_assets(&stg, OWNER);
            assert!(cur_collaterals == collaterals_before, 0);

            logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, OWNER, 100);
            let (collaterals_after, _) = storage::get_user_assets(&stg, OWNER);
            vector::pop_back(&mut cur_collaterals);

            assert!(cur_collaterals == collaterals_after, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should repay successfully when amount < loan
    public fun test_execute_repay_under_loan() {
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, OWNER, 20000000_000000000);

            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, OWNER, 10000000_000000000);

            logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, OWNER, 10000000_000000000);

            let loan = logic::user_loan_balance(&mut stg, 0, OWNER);

            assert!(loan == 0, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should repay successfully with a large amount
    public fun test_execute_repay_large() {
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, OWNER, 2000000000000_000000000);

            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, OWNER, 1000000000000_000000000);
            let loan = logic::user_loan_balance(&mut stg, 0, OWNER);
            assert!(loan == 1000000000000_000000000, 0);

            logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, OWNER, 1000000000000_000000000);

            let loan = logic::user_loan_balance(&mut stg, 0, OWNER);

            assert!(loan == 0, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate successfully with amount over max_liquidable value and skip excess amount
    // Should return correct data for amount under max_liquidable value
    public fun test_execute_liquidate_excess() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000);

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            ); 

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob));
            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 0, 5000_000000000);
            lib::printf(b"Data Before Liquidation");
            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);
            // 10ETH * 35%
            assert!(liquidable_balance_in_collateral == 3500000000, 1);
            // 10ETH * 1300ETHPrice * 35%
            assert!(liquidable_balance_in_debt == 4550000000000, 2);
            // ((4550 * 5%) * (1 - 10%)) / 1300 * 1e9 = 157500000
            assert!(executor_bonus_balance == 157500000, 1);
            // ((4550 * 0.05) * 0.1) / 1300 * 1e9 = 17500000
            assert!(treasury_balance == 17500000, 2);
            assert!(!is_max_loan_value, 2);

            let (
                collateral_balance,
                excess_amount,
                treasury_reserved_collateral_balance
            ) = logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 0, 5000_000000000);

            let health_f = logic::is_health(&clock, &price_oracle, &mut stg, bob);
            lib::printf(b"After Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&health_f);

            // confusing variable name:
            // excess amount: real excess amount + bonus
            // bonus_balance = balance in collteral asset with actual liquidated value - reserve amount

            /*
                Fixed confusing issues:
                    In execute_liquidate_for_testing function, return 3 balances
                        - Amount of collateral the executor should receive, it should be (maximum liquidation amount + bonus)
                        - Excess repayment amount, user overpays for repayment
                        - Treasury reserved balance
            */

            // excess = 5000 - 4550(max) + 227.5(bonus)
            lib::print(&collateral_balance); // 3.4825, value = 3.4825 * 1300 = 4527.25
            lib::print(&excess_amount); // 677.5 value = 677.5
            lib::print(&treasury_reserved_collateral_balance); // 0.0175 = 22.75
            lib::print(&logic::user_collateral_value(&clock, &price_oracle, &mut stg, 1, bob)); // 8450_000000000 = 13000 - 4550
            lib::print(&logic::user_loan_value(&clock, &price_oracle, &mut stg, 0, bob)); // 5450_000000000 = 10000 - 4550

            // As calculated above: 3500000000 + 157500000 = 3657500000
            assert!(collateral_balance == 3657500000, 1);
            // As calculated above: 5000_000000000 - 4550_000000000 = 450000000000
            assert!(excess_amount == 450000000000, 1);
            assert!(treasury_reserved_collateral_balance == 17500000, 1);
            
            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) > 1, 1);
            assert!(health_f, 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate large amount
    public fun test_execute_liquidate_excess_large() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_00000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_00000_000000000);
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_00000_000000000);

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            ); 

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob));
            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 0, 5000_00000_000000000);
            lib::printf(b"Data Before Liquidation");
            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);
            // 10ETH * 35%
            assert!(liquidable_balance_in_collateral == 3500000000_00000, 1);
            // 10ETH * 1300ETHPrice * 35%
            assert!(liquidable_balance_in_debt == 4550000000000_00000, 2);
            // ((4550 * 5%) * (1 - 10%)) / 1300 * 1e9 = 157500000
            assert!(executor_bonus_balance == 157500000_00000, 1);
            // ((4550 * 0.05) * 0.1) / 1300 * 1e9 = 17500000
            assert!(treasury_balance == 17500000_00000, 2);
            assert!(!is_max_loan_value, 2);

            let (
                collateral_balance,
                excess_amount,
                treasury_reserved_collateral_balance
            ) = logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 0, 5000_00000_000000000);

            let health_f = logic::is_health(&clock, &price_oracle, &mut stg, bob);
            lib::printf(b"After Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&health_f);

            // excess = 5000 - 4550(max) + 227.5(bonus)
            lib::print(&collateral_balance); // 3.4825, value = 3.4825 * 1300 = 4527.25
            lib::print(&excess_amount); // 677.5 value = 677.5
            lib::print(&treasury_reserved_collateral_balance); // 0.0175 = 22.75
            lib::print(&logic::user_collateral_value(&clock, &price_oracle, &mut stg, 1, bob)); // 8450_000000000 = 13000 - 4550
            lib::print(&logic::user_loan_value(&clock, &price_oracle, &mut stg, 0, bob)); // 5450_000000000 = 10000 - 4550

            // As calculated above: 3500000000 + 157500000 = 3657500000
            assert!(collateral_balance == 3657500000_00000, 1);
            // As calculated above: 5000_000000000 - 4550_000000000 = 450000000000
            assert!(excess_amount == 450000000000_00000, 1);
            assert!(treasury_reserved_collateral_balance == 17500000_00000, 1);
            
            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) > 1, 1);
            assert!(health_f, 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate correctly after update_state 
    public fun test_execute_liquidate_after_update_state() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000);

            clock::increment_for_testing(&mut clock, 86400 * 1000 * 365 * 1);

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            ); 

            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                0,
                1_000000000,
            ); 
            logic::update_state_of_all_for_testing(&clock, &mut stg);
            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob));
            let (liquidable_collateral_balance,
            liquidable_loan_balance,
            bonus_balance,
            treasury_reserved_collateral_balance,
            excess_amount,
            is_max_loan_value) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 0, 5000_000000000);
            lib::printf(b"Data Before Liquidation");

            lib::print(&liquidable_collateral_balance);
            lib::print(&bonus_balance);
            lib::print(&liquidable_loan_balance);
            lib::print(&treasury_reserved_collateral_balance);
            lib::print(&excess_amount);
            lib::print(&is_max_loan_value);
            // 10 * 35%
            assert!(liquidable_collateral_balance == 3500000000, 1);
            // (4550 - 4550 * 10% * 5%) / 1300
            // FIXED: there are new liquidation logic
            // 10 * 35% * 5% * (1 - 10%)
            assert!(bonus_balance == 157500000, 1);
            // 13000 * 35%
            assert!(liquidable_loan_balance == 4550000000000, 2);
            // 4550 * 10% * 5% / 1300
            assert!(treasury_reserved_collateral_balance == 17500000, 2);
            assert!(!is_max_loan_value, 2);

            let (bonus_balance, excess_amount, treasury_reserved_collateral_balance)  = logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 0, 5000_000000000);

            let health_f = logic::is_health(&clock, &price_oracle, &mut stg, bob);
            lib::printf(b"After Liquidation");
            lib::print_index(&mut stg, 0);
            lib::print_balance(&mut stg, 0); // 27013000068149, 5533479212230 ~= 10000 - 4550 / 1.018


            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&health_f);

            lib::print(&bonus_balance); 
            lib::print(&excess_amount); 
            lib::print(&treasury_reserved_collateral_balance); 
            lib::print(&logic::user_collateral_value(&clock, &price_oracle, &mut stg, 1, bob)); // 8450_000000000 = 13000 - 4550
            lib::print(&logic::user_loan_value(&clock, &price_oracle, &mut stg, 0, bob)); // 10000 * 1.0186 - 4550 = 5637

            assert!(bonus_balance == 157500000 + 3500000000, 1);
            assert!(excess_amount == 450000000000, 1);
            assert!(treasury_reserved_collateral_balance == 17500000, 1);
            
            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) > 1, 1);
            assert!(health_f, 1);
            //scaled balance changed
            // 10000 * 1.0186 - 4550 = 5637
            lib::close_to(logic::user_loan_value(&clock, &price_oracle, &mut stg, 0, bob), 5637_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate successfully when asset_id != storage_id for the same asset
    public fun test_liquidate_with_mismatched_id() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_edge_global_2::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000); // alice supply 27000 usdt
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, alice, 100_000000000); // alice supply 100 usdc -> 100_000000(1e6 to 1e9)

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000); // bob supply 10 eth
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000); // bob borrow 10000 usdt
            logic::execute_borrow_for_testing<USDC_TEST>(&clock, &price_oracle, &mut stg, 3, bob, 1_000000000); // bob borrow 1 usdc -> 1000000(1e6 to 1e9)

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                3,
                1300_000000000,
            ); // ETH price from 1800 to 1300

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            let (_, loans) = storage::get_user_assets(&stg, bob);
            assert!(vector::length(&loans) == 2, 0);

            let bob_health_factor = logic::user_health_factor(&clock, &mut stg, &price_oracle, bob);
            std::debug::print(&bob_health_factor);

            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 3, 1_000000000); // collateral: eth, debt: usdc

            lib::printf(b"Data Calculate Before Liquidation");
            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);
            // (1 / 1300) * 1e9
            assert!(liquidable_balance_in_collateral == 769230, 1);
            // (1 / 1) * 1e9
            assert!(liquidable_balance_in_debt == 1000000000, 2);
            // liquidation bonus = 5%, treasury factor = 10%
            // total bonus = 1 * 5% = 0.05
            // treasury = 0.05 * 10% = 0.005
            // executor bonus = 0.05 - 0.005 = 0.045
            // bonus balance = 0.045 / 1300 * 1e9 = 34615
            // treasury balance = 0.005 / 1300 * 1e9 = 3846
            assert!(executor_bonus_balance == 34615, 1);
            assert!(treasury_balance == 3846, 2);
            assert!(is_max_loan_value, 2);
            // total repay amount - liquidable debt balance = 1 - 1 = 0
            assert!(executor_excess_balance == 0, 3);

            logic::execute_liquidate_for_testing<USDC_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 3, 1_000000000);

            lib::printf(b"After Liquidation");
            let (_, loans) = storage::get_user_assets(&stg, bob);
            let loan = vector::borrow(&loans, 0);
            assert!(*loan == 0, 0);
            let (bob_eth_supply_balance, bob_eth_borrow_balance) = storage::get_user_balance(&mut stg, 1, bob);
            lib::print(&bob_eth_supply_balance);
            lib::print(&bob_eth_borrow_balance);
            // before eth balance - (collateral balance + bonus balance + treasury balance)
            // 10 * 1e9 - (769230 + 34615 + 3846)
            assert!(bob_eth_supply_balance == 9999192309, 4);
            assert!(bob_eth_borrow_balance == 0, 4);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate successfully for new added asset with existed oracle
    public fun test_liquidate_with_new_asset() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_edge_global_2::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000); // alice supply 27000 usdt
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, alice, 100_000000000); // alice supply 100 usdc -> 100_000000(1e6 to 1e9)

            logic::execute_deposit_for_testing<ETH2_TEST>(&clock, &mut stg, 6, bob, 10_000000000); // bob supply 10 eth
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000); // bob borrow 10000 usdt
            logic::execute_borrow_for_testing<USDC_TEST>(&clock, &price_oracle, &mut stg, 3, bob, 1_000000000); // bob borrow 1 usdc -> 1000000(1e6 to 1e9)

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                3,
                1300_000000000,
            ); // ETH price from 1800 to 1300

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            let (_, loans) = storage::get_user_assets(&stg, bob);
            assert!(vector::length(&loans) == 2, 0);

            let bob_health_factor = logic::user_health_factor(&clock, &mut stg, &price_oracle, bob);
            std::debug::print(&bob_health_factor);

            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 6, 3, 1_000000000); // collateral: eth, debt: usdc

            lib::printf(b"Data Calculate Before Liquidation");
            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);
            // (1 / 1300) * 1e9
            assert!(liquidable_balance_in_collateral == 769230, 1);
            // (1 / 1) * 1e9
            assert!(liquidable_balance_in_debt == 1000000000, 2);
            // liquidation bonus = 5%, treasury factor = 10%
            // total bonus = 1 * 5% = 0.05
            // treasury = 0.05 * 10% = 0.005
            // executor bonus = 0.05 - 0.005 = 0.045
            // bonus balance = 0.045 / 1300 * 1e9 = 34615
            // treasury balance = 0.005 / 1300 * 1e9 = 3846
            assert!(executor_bonus_balance == 34615, 1);
            assert!(treasury_balance == 3846, 2);
            assert!(is_max_loan_value, 2);
            // total repay amount - liquidable debt balance = 1 - 1 = 0
            assert!(executor_excess_balance == 0, 3);

            logic::execute_liquidate_for_testing<USDC_TEST, ETH2_TEST>(&clock, &price_oracle, &mut stg, bob, 6, 3, 1_000000000);

            lib::printf(b"After Liquidation");
            let (_, loans) = storage::get_user_assets(&stg, bob);
            let loan = vector::borrow(&loans, 0);
            assert!(*loan == 0, 0);
            let (bob_eth_supply_balance, bob_eth_borrow_balance) = storage::get_user_balance(&mut stg, 6, bob);
            lib::print(&bob_eth_supply_balance);
            lib::print(&bob_eth_borrow_balance);
            // before eth balance - (collateral balance + bonus balance + treasury balance)
            // 10 * 1e9 - (769230 + 34615 + 3846)
            assert!(bob_eth_supply_balance == 9999192309, 4);
            assert!(bob_eth_borrow_balance == 0, 4);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }
    #[test]
    // A case to detect error in liqudation balance management
    // Update: Fixed
    public fun test_execute_liquidate_excess_balance_error() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000); // alice supply 27000 usdt
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, alice, 10_000000000); // alice supply 10 eth

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000); // bob supply 10 eth
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000); // bob borrow 10000 usdt

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            ); // eth price from 1800 to 1300

            // bob deposits 10 ETH and borrow 10000 USDT
            // after price drop, bob's collecteral value 18000U -> 13000U

            // liquidate bob's position with maximum value 13000 * 35% =  4550U
            logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 0, 4550_000000000);

            lib::printf(b"After Liquidation");

            // fixed: bob's collateral has been deductions with bonuses and treasury
            // total bonus = executor bonus + treasury = 4550 * 5% = 227.5
            // bob's collateral is 13000 - 4550 - 227.5 = 8222.5
            lib::print(&logic::user_collateral_value(&clock, &price_oracle, &mut stg, 1, bob));
            lib::print(&logic::user_loan_value(&clock, &price_oracle, &mut stg, 0, bob)); // 5450_000000000 = 10000 - 4550

            // repay bob's loan
            logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 5450_000000000);

            // withdraw bob's colletral
            let withdraw_amount = logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 10_000000000);
            lib::print(&withdraw_amount);
           
            // 8222.5 / 1300 * 1e9
            assert!(withdraw_amount == 6325000000, 2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate successfully with amount under max_liquidable value and return correct bonus and treasury
    // Should return correct data for amount over max_liquidable value
    public fun test_execute_liquidate() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000);

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            );

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob));

            let (
                liquidable_collateral_balance,
                liquidable_loan_balance,
                bonus_balance,
                treasury_reserved_collateral_balance,
                excess_amount,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 0, 2000_000000000);

            lib::printf(b"Data Before Liquidation");
            lib::print(&liquidable_collateral_balance);
            lib::print(&liquidable_loan_balance);
            lib::print(&bonus_balance);
            lib::print(&treasury_reserved_collateral_balance);
            lib::print(&excess_amount);
            lib::print(&is_max_loan_value);
            // 2000 / 1300
            assert!(liquidable_collateral_balance == 1538461538, 1);
            assert!(liquidable_loan_balance == 2000000000000, 2);
            // (2000 * 5%) * (1 - 10%) / 1300 * 1e9 = 69230769
            assert!(bonus_balance == 69230769, 1);
            // 10 / 1300
            assert!(treasury_reserved_collateral_balance == 7692307, 2);
            assert!(!is_max_loan_value, 2);

            let (collateral_balance, excess_amount, treasury_reserved_collateral_balance)  = logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 0, 2000_000000000);

            let health_f = logic::is_health(&clock, &price_oracle, &mut stg, bob);
            lib::printf(b"After Liquidation");
            lib::print(&logic::user_health_factor(&clock, &mut stg, &price_oracle, bob));
            lib::print(&health_f);

            // confusing variable name:
            // excess amount: real excess amount + bonus
            // bonus_balance = balance in collteral asset with actual liquidated value - reserve amount

            lib::print(&collateral_balance);
            lib::print(&excess_amount); 
            lib::print(&treasury_reserved_collateral_balance); 
            // 1538461538 + 69230769 = 1607692307
            assert!(collateral_balance == 1607692307, 1);
            // input 2000 - repay 2000 = 0
            assert!(excess_amount == 0, 1);
            // 10 / 1300
            assert!(treasury_reserved_collateral_balance == 7692307, 1);
            
            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) > 1, 1);
            assert!(health_f, 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should update correct interest rate and balance after liquidation 
    public fun test_execute_liquidate_rate() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000);

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            );

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            let (usdt_supply_r, usdt_borrow_r) = storage::get_current_rate(&mut stg, 0);
            let (eth_supply_r, eth_borrow_r) = storage::get_current_rate(&mut stg, 1);
            let (s_before, b_before) = storage::get_total_supply(&mut stg, 1);

            lib::print(&usdt_supply_r );
            lib::print(&usdt_borrow_r );
            
            lib::print(&eth_supply_r );
            lib::print(&eth_borrow_r );

            lib::print(&s_before );
            lib::print(&b_before );

            assert!(s_before == 10_000000000, 2);
            assert!(b_before == 0, 2);

            logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 0, 4550_000000000);

            lib::printf(b"After Liquidation");
            let (usdt_supply_r_after, usdt_borrow_r_after) = storage::get_current_rate(&mut stg, 0);
            let (eth_supply_r_after, eth_borrow_r_after) = storage::get_current_rate(&mut stg, 1);
            let (s_after, b_after) = storage::get_total_supply(&mut stg, 1);

            lib::print(&eth_supply_r_after );
            lib::print(&eth_borrow_r_after );
            lib::print(&usdt_supply_r_after );
            lib::print(&usdt_borrow_r_after );

            lib::print(&s_after );
            lib::print(&b_after );

            assert!(eth_supply_r_after == 0, 1);
            assert!(eth_borrow_r_after == ray_math::ray() / 100, 1);
            assert!(usdt_supply_r_after < usdt_supply_r, 2);
            assert!(usdt_borrow_r_after < usdt_borrow_r, 2);
            assert!(s_after == 6_325000000, 2);
            assert!(b_after == 0, 2);
            
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should liquidate successfully with full loan and clear user's loan
    // Should return correct data for repaying full loan
    public fun test_execute_liquidate_full_repay() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000); // alice supply 27000 usdt
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, alice, 100_000000000); // alice supply 100 usdc -> 100_000000(1e6 to 1e9)

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000); // bob supply 10 eth
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000); // bob borrow 10000 usdt
            logic::execute_borrow_for_testing<USDC_TEST>(&clock, &price_oracle, &mut stg, 3, bob, 1_000000000); // bob borrow 1 usdc -> 1000000(1e6 to 1e9)

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            ); // ETH price from 1800 to 1300

            // liquidate bob's position
            lib::printf(b"Before Liquidation");
            let (_, loans) = storage::get_user_assets(&stg, bob);
            assert!(vector::length(&loans) == 2, 0);

            let bob_health_factor = logic::user_health_factor(&clock, &mut stg, &price_oracle, bob);
            std::debug::print(&bob_health_factor);

            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 3, 1_000000000); // collateral: eth, debt: usdc

            lib::printf(b"Data Calculate Before Liquidation");
            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);
            // (1 / 1300) * 1e9
            assert!(liquidable_balance_in_collateral == 769230, 1);
            // (1 / 1) * 1e9
            assert!(liquidable_balance_in_debt == 1000000000, 2);
            // liquidation bonus = 5%, treasury factor = 10%
            // total bonus = 1 * 5% = 0.05
            // treasury = 0.05 * 10% = 0.005
            // executor bonus = 0.05 - 0.005 = 0.045
            // bonus balance = 0.045 / 1300 * 1e9 = 34615
            // treasury balance = 0.005 / 1300 * 1e9 = 3846
            assert!(executor_bonus_balance == 34615, 1);
            assert!(treasury_balance == 3846, 2);
            assert!(is_max_loan_value, 2);
            // total repay amount - liquidable debt balance = 1 - 1 = 0
            assert!(executor_excess_balance == 0, 3);

            logic::execute_liquidate_for_testing<USDC_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 3, 1_000000000);

            lib::printf(b"After Liquidation");
            let (_, loans) = storage::get_user_assets(&stg, bob);
            let loan = vector::borrow(&loans, 0);
            assert!(*loan == 0, 0);
            let (bob_eth_supply_balance, bob_eth_borrow_balance) = storage::get_user_balance(&mut stg, 1, bob);
            lib::print(&bob_eth_supply_balance);
            lib::print(&bob_eth_borrow_balance);
            // before eth balance - (collateral balance + bonus balance + treasury balance)
            // 10 * 1e9 - (769230 + 34615 + 3846)
            assert!(bob_eth_supply_balance == 9999192309, 4);
            assert!(bob_eth_borrow_balance == 0, 4);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    /*
        1.A deposit and borrow in multiple pools
        2.Time passes for a year, index changed
        3. Set oracle price to trigger h_f < 1 for A
        4. B performs liquidation
        5.Time passes for a year, index changed
        6. Set oracle price to trigger h_f < 1 for A
        7. B performs liquidation
        8. compare wtih the data in control group, including index, balance, fund balance, rate, treasury
    */
    #[test]
    #[allow(unused_variable)]
    public fun test_liquidate_integration() { 
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            
            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 3650 * 1000);

            // alice provides base balance for pools
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 12000_000000000); 
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, alice, 120_000000000);

            // bob deposits eth and borrow usdt and usdc
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000); // bob supply 10 eth
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000); // bob borrow 10000 usdt
            logic::execute_borrow_for_testing<USDC_TEST>(&clock, &price_oracle, &mut stg, 3, bob, 100_000000000); // bob borrow 100 usdc 

            //update time, price and states 
            {
                // pass a year, utilzation rate ~= 80% 
                clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);

                // drop the ETH price
                oracle::update_token_price(
                    &oracle_feeder_cap,
                    &clock,
                    &mut price_oracle,
                    1,
                    1452_000000000,
                ); // ETH price from 1800 to 1452(an edge price to liquidate)
                logic::update_state_of_all_for_testing(&clock, &mut stg);
            };

            
            let (s_eth, b_eth) = storage::get_user_balance(&mut stg, 1, bob);
            let (s_usdc, b_usdc) = storage::get_user_balance(&mut stg, 3, bob);
            let (s_i_eth, b_i_eth) = storage::get_index(&mut stg, 1);
            let (s_i_usdc, b_i_usdc) = storage::get_index(&mut stg, 3);

            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 3, 100_000000000); // collateral: eth, debt: usdc

            lib::printf(b"Data Calculate Before Liquidation1");
            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);

            lib::printf(b"Balance and Index Before Liquidation1");
            lib::print(&s_eth); // 10000000000
            lib::print(&b_eth); // 0
            lib::print(&s_usdc); // 0
            lib::print(&b_usdc); // 100000000000

            lib::print(&s_i_eth); // 1000000000000000000000000000
            lib::print(&b_i_eth); // 1010049999998531186363752000
            lib::print(&s_i_usdc); // 1122999999999999999999999999
            lib::print(&b_i_usdc); // 1178185033775516321554192000

            // (1 / 1452) * 1e9
            assert!(liquidable_balance_in_collateral == 68870523, 1);

            // liquidable_balance_in_collateral * (5% - 0.5%)
            assert!(executor_bonus_balance == 3099173, 1);

            // liquidable_balance_in_collateral * 0.5%
            assert!(treasury_balance == 344352, 1);

            assert!(executor_excess_balance == 0, 1);
            assert!(!is_max_loan_value, 1);


            // (100 / 1) * 1e9
            assert!(liquidable_balance_in_debt == 100_000000000, 2);

            logic::execute_liquidate_for_testing<USDC_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 3, 100_000000000);

            lib::printf(b"After Liquidation1");
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob)); // true

            let (bob_eth_supply_balance, bob_eth_borrow_balance) = storage::get_user_balance(&mut stg, 1, bob);
            lib::print(&bob_eth_supply_balance); // 9_927685952
            lib::print(&bob_eth_borrow_balance); // 0

            let (bob_usdc_supply_balance, bob_usdc_borrow_balance) = storage::get_user_balance(&mut stg, 3, bob);
            lib::print(&bob_usdc_supply_balance); // 0
            lib::print(&bob_usdc_borrow_balance); // 15_123688442

            // 10 - (100 * (1 + 5%)) 1452 ~= 9.927
            assert!(bob_eth_supply_balance / 1_000000  == 9927, 2);

            // 100 - 100 / 1.17 ~= 15
            assert!(bob_usdc_borrow_balance / 1_000000000  == 15, 2);


            //update time, price and states 
            {
                // pass a year, utilzation rate ~= 80% 
                clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
                logic::update_state_of_all_for_testing(&clock, &mut stg);
            };

            // liquidation2 part
            let (s_eth, b_eth) = storage::get_user_balance(&mut stg, 1, bob);
            let (s_usdc, b_usdc) = storage::get_user_balance(&mut stg, 3, bob);
            let (s_i_eth, b_i_eth) = storage::get_index(&mut stg, 1);
            let (s_i_usdc, b_i_usdc) = storage::get_index(&mut stg, 3);

            let (
                liquidable_balance_in_collateral,
                liquidable_balance_in_debt,
                executor_bonus_balance,
                treasury_balance,
                executor_excess_balance,
                is_max_loan_value
            ) = logic::calculate_liquidation_for_testing(&clock, &mut stg, &price_oracle, bob, 1, 3, 100_000000000); // collateral: eth, debt: usdc

            lib::printf(b"Data Calculate Before Liquidation2");
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob)); // false

            lib::print(&liquidable_balance_in_collateral);
            lib::print(&liquidable_balance_in_debt);
            lib::print(&executor_bonus_balance);
            lib::print(&treasury_balance);
            lib::print(&executor_excess_balance);
            lib::print(&is_max_loan_value);
 
            let (bob_usdc_supply_balance, bob_usdc_borrow_balance) = storage::get_user_balance(&mut stg, 3, bob);
            lib::print(&bob_usdc_supply_balance); // 0
            lib::print(&bob_usdc_borrow_balance); // 15_123688442
            
            // 15.123688(USDC_borrow) * 1.19 / 1452 ~= 0.0124
            assert!(liquidable_balance_in_collateral / 100000 == 124, 1);

            // liquidable_balance_in_collateral * (5% - 0.5%)

            assert!(executor_bonus_balance / 10000 == 55, 1);

            // liquidable_balance_in_collateral * 0.5%
            assert!(treasury_balance / 1000 == 62, 1);

            // 100 - 15 * 1.19 ~= 82
            assert!(executor_excess_balance / 1000000000 == 81, 1);
            assert!(is_max_loan_value, 1);

            lib::printf(b"Balance and Index Before Liquidation2");
            lib::print(&s_eth); // 9927685952
            lib::print(&b_eth); // 0
            lib::print(&s_usdc); // 0
            lib::print(&b_usdc); // 15123688442

            lib::print(&s_i_eth); // 1000000000000000000000000000
            lib::print(&b_i_eth); // 1020201002497032849573417573
            //index wouble 1124413620047336586869474621 1190713693753498517894675021 if not add treasury to supply balance
            lib::print(&s_i_usdc); // 1124376965732376394036543984
            lib::print(&b_i_usdc); // 1190549347695393706165748710

            let (
                collateral_balance,
                excess_amount,
                treasury_reserved_collateral_balance
            ) = logic::execute_liquidate_for_testing<USDC_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, bob, 1, 3, 100_000000000);

            lib::printf(b"After Liquidation2");
            lib::print(&logic::is_health(&clock, &price_oracle, &mut stg, bob));

            let (bob_eth_supply_balance, bob_eth_borrow_balance) = storage::get_user_balance(&mut stg, 1, bob);
            lib::print(&bob_eth_supply_balance); // 9_914540115
            lib::print(&bob_eth_borrow_balance); // 0

            let (bob_usdc_supply_balance, bob_usdc_borrow_balance) = storage::get_user_balance(&mut stg, 3, bob);
            lib::print(&bob_usdc_supply_balance); // 0
            lib::print(&bob_usdc_borrow_balance); // 0

            // 9.927 - (0.0125 * 1.05) + ~= 9.91
            assert!(bob_eth_supply_balance / 1_0000000  == 991, 2);

            // 100 - 100 / 1.17 ~= 15
            assert!(bob_usdc_borrow_balance == 0, 2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };
        test_scenario::end(scenario);
    }


    #[test]
    // Should receive treasury balance when current index > 1 in update_state
    public fun test_update_state_add_treasury () {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);

            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000);

            // deposit 10000U and borrow 8500U
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 8500_000000000);

            clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
            logic::update_state_for_testing(&clock, &mut stg, 0);
            lib::printf(b"past 1 year");
            lib::print_index(&mut stg, 0);
            let treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // 1.0991 * 8500 * 0.07 / 1.0747 = 54.8
            lib::close_to(treasury, 54_800000000, 0);


            clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
            logic::update_state_for_testing(&clock, &mut stg, 0);
            lib::printf(b"past 1 year");
            lib::print_index(&mut stg, 0);
            let  treasury = storage::get_treasury_balance(&mut stg, 0);
            lib::print(&treasury);
            // 54.8 + (1.208 - 1.0991) * 8500 * 0.07 / 1.15498 = 110.9
            lib::close_to(treasury, 110_900000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // A case to test extreme situation
    // Todo: set assert
    public fun test_execute_rate_edge() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        // 0 reserve factor 0 treasury factor for usdt
        sup_edge_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            // deposit
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  

            lib::printf(b"init rate");
            let (s,b) = storage::get_current_rate(&mut stg, 0);

            lib::print(&s); 
            lib::print(&b);

            // borrow
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 8500_000000000);

            // borrow_ratio * u = supply_ratio
            // rate 
            // rate_l rate_conpound
            lib::printf(b"index before");
            let (s, b) = storage::get_index(&mut stg, 0);
            lib::print(&s); // 1
            lib::print(&b); // 1
            let util_p = calculator::caculate_utilization(&mut stg, 0) * 100 / ray_math::ray();
            lib::print(&util_p); // 85
            (s, b) = storage::get_total_supply(&mut stg, 0);
            lib::print(&s); // 10000000000000 -> 10000
            lib::print(&b); // 8500000000000 -> 8500

            // 6 year past, same price updated
            clock::increment_for_testing(&mut clock, 86400 * 1000 * 365 * 6);
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                0,
                1_000000000,
            );

            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1800_000000000,
            );

            // logic::update_state_of_all_for_testing(& clock, &mut stg);

            //repay all the money
            logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 15847_000000000);
            //ensure all the money repaied
            let (_, loans) = storage::get_user_assets(&stg, bob);
            let loan_len = vector::length (&loans);
            assert!(loan_len == 0, 1);

            lib::printf(b"index after repaied");
            let (s, b) = storage::get_index(&mut stg, 0);
            lib::print(&s); // 1532950000000000000000000000 -> 1.5
            lib::print(&b); // 1864211154343442990018704000 -> 1.8

            // logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 11500_000000000);
            // logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, alice, 12320_000000000);
            // logic::update_state_of_all_for_testing(& clock, &mut stg);

            (s, b) = storage::get_total_supply(&mut stg, 0);
            lib::print(&s); //13476630027072 -> 13476
            lib::print(&b); // 3940430672139 -> 3940
            let util_p = calculator::caculate_utilization(&mut stg, 0) * 100 / ray_math::ray();
            lib::print(&util_p); //35

            (s,b) = storage::get_current_rate(&mut stg, 0);

            lib::print(&s); //009877364830798074914277326 -> util_rate != 0, no borrow but still has interest 
            lib::print(&b); //027778679538987850331574616 
            

            lib::printf(b"index after withdrawing all possible money"); 
            // will revert if more than 13300
            logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, alice, 13300_000000000);
            let (s, b) = storage::get_index(&mut stg, 0);
            lib::print(&s); // 1532950000000000000000000000 -> 1.5
            lib::print(&b); // 1864211154343442990018704000 -> 1.8

            (s, b) = storage::get_total_supply(&mut stg, 0);
            lib::print(&s); // 4800547963078 -> 4800
            lib::print(&b); // 3940430672139 -> 3940
            let util_p = calculator::caculate_utilization(&mut stg, 0) * 100 / ray_math::ray();
            lib::print(&util_p); //99

            // eve deposit, alice gets money back
            let eve = @0xc0c;
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, eve, 10000_000000000);
            let withdrawable = logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, alice, 4000_000000000);

            lib::printf(b"alice withdrawable after eve deposit");
            lib::print(&withdrawable); // 2029500000000 -> 2029, 2029 + 13300 = 15329 (equal supply index amount)
            
            // eve interest rate
            lib::printf(b"index after eve deposit 6 years");
            clock::increment_for_testing(&mut clock, 86400 * 1000 * 365 * 6);
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                0,
                1_000000000,
            );

            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1800_000000000,
            );


            let _ = logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, eve, 1_000000000);
            let (s, b) = storage::get_index(&mut stg, 0);
            lib::print(&s); // 1682626454677605711897575059 -> 1.68 (from 1.5)
            lib::print(&b); // 2284862477052448511367825599 -> 2.28

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    // Should update successfully for index,rate, timestamp and balance
    // Should update index normally and not add balance when update_state
    // Should add balance to treasury when update_state  
    // Should user balance not chenge for update_state
    // Should update borrow_rate and supply_rate successfully
    // Should scale treasury with supply index
    // Should receive treasury balance when current index = 1 in update_state
    #[test]
    #[allow(unused_variable)]
    public fun test_update_state () {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            
            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000);

            // deposit 10000U
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  

            lib::printf(b"deposit usdt");
            lib::print_rate(&mut stg, 0);
            
            // borrow 8500U
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 8500_000000000);

            lib::printf(b"rate after borrowing 85% USDT");
            lib::print_rate(&mut stg, 0); // 074702250000000000000000000 094500000000000000000000000

            lib::printf(b"balance of a and b");
            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            lib::print(&s);
            lib::print(&b);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            lib::print(&s);
            lib::print(&b);

            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_for_testing(&clock, &mut stg, 0);

            lib::printf(b"past 1 year");

            lib::print_index(&mut stg, 0);
            let (s, b) = storage::get_index(&mut stg, 0);
            // supply rate == index after 1 year 
            assert!(s == 1074702250000000000000000000, 0);
            lib::print_index(&mut stg, 0); // 1074702250000000000000000000 1099106259067283085220744000

            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 10000_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            assert!(s == 0, 0);
            assert!(b == 8500_000000000, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 1, bob);
            assert!(s == 10_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            // 10000 + (1.099 - 1) * 8500 * 0.07 / 1.0747 ~= 10054
            lib::close_to(s, 10054_000000000, 0);
            assert!(b == 8500_000000000, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 1);
            assert!(s == 10_000000000, 0);
            assert!(b == 0, 0);

            let  treasury = storage::get_treasury_balance(&stg, 0);
            lib::print(&treasury);
            // (1.099 - 1) * 8500 * 0.07 / 1.0747 ~= 54
            lib::close_to(treasury, 54_000000000, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    #[allow(unused_variable)]
    public fun test_update_state_large () {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            
            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000);

            // deposit 1000000000U
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 1000000000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 1000000_000000000);  

            lib::printf(b"deposit usdt");
            lib::print_rate(&mut stg, 0);
            
            // borrow 850000000U
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 850000000_000000000);

            lib::printf(b"rate after borrowing 85% USDT");
            lib::print_rate(&mut stg, 0); // 074702250000000000000000000 094500000000000000000000000

            lib::printf(b"balance of a and b");
            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            lib::print(&s);
            lib::print(&b);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            lib::print(&s);
            lib::print(&b);

            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_for_testing(&clock, &mut stg, 0);

            lib::printf(b"past 1 year");

            lib::print_index(&mut stg, 0);
            let (s, b) = storage::get_index(&mut stg, 0);
            // supply rate == index after 1 year 
            lib::print_index(&mut stg, 0); // 1088825000000000000000000000 1110148303771919768949784000
            assert!(s == 1074702250000000000000000000, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 1000000000_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            assert!(s == 0, 0);
            assert!(b == 850000000_000000000, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 1, bob);
            assert!(s == 1000000_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            // 10000 + (1.099 - 1) * 8500 * 0.07 / 1.0747 ~= 10054
            lib::close_to(s, 10054_00000_000000000, 100000_000000000);
            assert!(b == 850000000_000000000, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 1);
            assert!(s == 1000000_000000000, 0);
            assert!(b == 0, 0);

            let  treasury = storage::get_treasury_balance(&stg, 0);
            lib::print(&treasury);
            // (1.099 - 1) * 8500 * 0.07 / 1.0747 ~= 54
            lib::close_to(treasury, 5400000_000000000, 100000_000000000);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };
        test_scenario::end(scenario);
    }
    
    /*
        1. A deposits SUI and USDC, B deposits USDC 
        2. B borrows maximum SUI
        3. 1 year past
        4. B repays half debt and withdraw a part of USDC
        5. 1 year past
        6. B repays all debt and withdraw all USDC
        7. A withdraw all SUI and USDC
        8. Should calculate correctly for interests, balances, indices, treasury, etc. 
    */
    #[test]
    #[allow(unused_variable)]
    public fun test_update_state_integration_1 () {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            
            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000000);

            // deposit 10000U
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, alice, 10_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  

            lib::printf(b"deposit usdt");
            lib::print_rate(&mut stg, 0);
            
            // borrow 9000U
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 9000_000000000);

            lib::printf(b"rate after borrowing 90% USDT");
            lib::print_rate(&mut stg, 0); // 124713000000000000000000000 149000000000000000000000000

            lib::printf(b"balance of a and b");
            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            lib::print(&s);
            lib::print(&b);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            lib::print(&s);
            lib::print(&b);

            lib::printf(b"past 1 year");
            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_for_testing(&clock, &mut stg, 0);

            lib::print_index(&mut stg, 0); // 1124713000000000000000000000 1160649354904960155468616000

            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 10000_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            assert!(s == 0, 0);
            assert!(b == 9000_000000000, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 1, bob);
            assert!(s == 10_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            //  10000 + 9000 * (1.16 - 1) * 0.07 / 1.1247
            lib::close_to(s, 10089_000000000, 0);
            assert!(b == 9000_000000000, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 1);
            assert!(s == 20_000000000, 0);
            assert!(b == 0, 0);

            lib::print_index(&mut stg, 0);
            let (s, b) = storage::get_index(&mut stg, 0);
            // supply rate == index after 1 year 
            assert!(s == 1124713000000000000000000000, 0);

            let  treasury = storage::get_treasury_balance(&stg, 0);
            lib::print(&treasury);
            // supply - 10000
            lib::close_to(treasury, 89_000000000, 0);

            // B repays half debt and withdraw a part of USDT, 3eth
            logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 4500_000000000);
            logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 3_000000000);

            lib::printf(b"past 1 year");
            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_of_all_for_testing(&clock, &mut stg);
            lib::print_index(&mut stg, 0); // 1139069782094821044482350741 1191459195740992139396126531
            lib::print_rate(&mut stg, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            lib::print(&s);
            lib::print(&b);
            assert!(b > 4500_000000000, 0);

            let (s,b) = storage::get_current_rate(&mut stg, 0);
            assert!(b > 0 && b < ray_math::ray() / 10, 0);
            assert!(s > 0 && s < b, 0);

            // 6. B repays all debt and withdraw all USDT
            let excess = logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 6200_000000000);
            let amount = logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 10_000000000);
            lib::print(&amount);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            lib::print(&s);
            lib::print(&b);
            assert!(b == 0, 0);
            assert!(excess < 100_000000000, 0);
            assert!(amount == 7_000000000, 0); 

            //  7. A withdraw all ETH and USDT
            lib::printf(b"A withdraws all");

            let amount_u = logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, alice, 11393_293282359);
            let amount_e = logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, alice, 10_000000000);

            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 0, 0);
            let (s, b) = storage::get_user_balance(&mut stg, 1, alice);
            assert!(s == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            // 89 + (1.191 - 1.16) * (9000 - 4500 / 1.16) * 0.07 / 1.139 ~= 99
            lib::close_to(s, 99_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 1);
            assert!(s == 0, 0);
            assert!(b == 0, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };
        test_scenario::end(scenario);
    }

    // Should update states for multiple assets
    // TODO: implement 
    #[test]
    #[allow(unused_variable)]
    public fun test_update_state_all () {
        let alice = @0xace;
        let bob = @0xb0b;
        let eve = @0xb0e;
        let scenario = test_scenario::begin(OWNER);

        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            
            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000);

            // deposit 10000U
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  

            lib::printf(b"deposit usdt");
            lib::print_rate(&mut stg, 0);
            
            // borrow 8500U
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 8500_000000000);
            logic::execute_borrow_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, alice, 1_000000000);

            lib::printf(b"rate after borrowing 85% USDT");
            lib::print_rate(&mut stg, 0); // 074702250000000000000000000 094500000000000000000000000

            lib::printf(b"balance of a and b");
            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            lib::print(&s);
            lib::print(&b);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            lib::print(&s);
            lib::print(&b);

            clock::increment_for_testing(&mut clock, 1000 * 86400 * 365);
            logic::update_state_of_all_for_testing(&clock, &mut stg);

            let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 10000_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 0, bob);
            assert!(s == 0, 0);
            assert!(b == 8500_000000000, 0);

            let (s, b) = storage::get_user_balance(&mut stg, 1, bob);
            assert!(s == 10_000000000, 0);
            assert!(b == 0, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 0);
            // 10000 + (1.099 - 1) * 8500 * 0.07 / 1.0747 ~= 10054
            lib::close_to(s, 10054_000000000, 0);
            assert!(b == 8500_000000000, 0);

            let (s, b) = storage::get_total_supply(&mut stg, 1);
            // supply includes treasury
            assert!(s > 10_000000000, 0);
            assert!(b == 1_000000000, 0);

            lib::printf(b"past 1 year");
            lib::print_index(&mut stg, 0);
            let (s, b) = storage::get_index(&mut stg, 0);
            // supply rate == index after 1 year 
            assert!(s == 1074702250000000000000000000, 0);

            let  treasury = storage::get_treasury_balance(&stg, 0);
            lib::print(&treasury);
            // (1.099 - 1) * 8500 * 0.07 / 1.0747 ~= 54
            lib::close_to(treasury, 54_000000000, 0);

            let (s, b) = storage::get_index(&mut stg, 0);
            assert!(b > s, 0);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should increase users balance with latest index
    // Should decrease users balance with latest index
    public fun test_modify_rate() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        // 0 reserve factor 0 treasury factor for usdt
        sup_edge_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            //init
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            // deposit
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);  

            lib::printf(b"init rate");
            let (s,b) = storage::get_current_rate(&mut stg, 0);

            lib::print(&s); 
            lib::print(&b);

            // borrow
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 8500_000000000);

            let (s, _) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 10000_000000000, 1);

            // increase alice supply
            logic::increase_supply_balance_for_testing(&mut stg, 0, alice, 10000_000000000);
            let (s, _) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 20000_000000000, 1);
 
             // decrease alice supply
            logic::decrease_supply_balance_for_testing(&mut stg, 0, alice, 10000_000000000);
            let (s, _) = storage::get_user_balance(&mut stg, 0, alice);
            assert!(s == 10000_000000000, 1);

            // increase bob borrow
            logic::increase_borrow_balance_for_testing(&mut stg, 0, bob, 1000_000000000);
            let (_, b) = storage::get_user_balance(&mut stg, 0, bob);
            assert!(b == 9500_000000000, 1);
 
             // decrease bob supply
            logic::decrease_borrow_balance_for_testing(&mut stg, 0, bob, 1000_000000000);
            let (_, b) = storage::get_user_balance(&mut stg, 0, bob);
            assert!(b == 8500_000000000, 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should return true only if health factor > 1
    public fun test_is_health() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 27000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000);

            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) > ray_math::ray(), 1);
            assert!(logic::is_health(&clock, &price_oracle, &mut stg, bob), 1);

            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            );

            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) < ray_math::ray(), 1);
            assert!(!logic::is_health(&clock, &price_oracle, &mut stg, bob), 1);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }


    #[test]
    // Should return correct health factor with certain health_collateral_value, health_loan_value, dynamic_liquidation_threshold
    // TODO: add calculation process in comment
    public fun test_health_factor() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {

            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 40000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            logic::execute_deposit_for_testing<BTC_TEST>(&clock, &mut stg, 2, bob, 1_000000000);
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, alice, 40000_000000000);


            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 10000_000000000);
            logic::execute_borrow_for_testing<USDC_TEST>(&clock, &price_oracle, &mut stg, 3, bob, 10000_000000000);
            let h_f = logic::user_health_factor(&clock, &mut stg, &price_oracle, bob);

            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) > ray_math::ray(), 1);    
            assert!(logic::is_health(&clock, &price_oracle, &mut stg, bob), 1);

            lib::print(&(h_f * 100 / ray_math::ray()));
            // liquidation_threshold price amount
            // 75% * 1800 * 10 + 27000 * 1 * 80% = 35100
            // borrow = 20000
            // h_f =  35100 / 20000 = 1.7550
            assert!((h_f * 10000 / ray_math::ray()) == 17550, 2);
            // drop the ETH price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                1,
                1300_000000000,
            );


            // drop the BTC price
            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                2,
                10000_000000000,
            );
            let h_f = logic::user_health_factor(&clock, &mut stg, &price_oracle, bob);
            assert!(logic::user_health_factor(&clock, &mut stg, &price_oracle, bob) < ray_math::ray(), 1);
            assert!(!logic::is_health(&clock, &price_oracle, &mut stg, bob), 1);
            lib::print(&(h_f * 100 / ray_math::ray()));
            // liquidation_threshold price amount
            // 75% * 1300 * 10 + 10000 * 1 * 80% = 17750
            // borrow = 20000
            // h_f =  17750 / 20000 = 0.8875
            assert!((h_f * 10000 / ray_math::ray()) == 8875, 2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should calculate correct threshold with 1/2/5 collaterals
    public fun test_dynamic_liquidation_threshold() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            //1
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            let d_threshold = logic::dynamic_liquidation_threshold(&clock, &mut stg, &price_oracle, bob);
            assert!((d_threshold * 100 / ray_math::ray()) == 75, 2);

            //2
            logic::execute_deposit_for_testing<BTC_TEST>(&clock, &mut stg, 2, bob, 1_000000000);
            let d_threshold = logic::dynamic_liquidation_threshold(&clock, &mut stg, &price_oracle, bob);
            assert!((d_threshold * 100 / ray_math::ray()) == 78, 2);

            //5
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, bob, 1000_000000000);
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, bob, 3000_000000000);
            logic::execute_deposit_for_testing<TEST_COIN>(&clock, &mut stg, 4, bob, 500000_000000000);
            // 38350 / 54000 = 0.71
            let d_threshold = logic::dynamic_liquidation_threshold(&clock, &mut stg, &price_oracle, bob);
            lib::print(&d_threshold); 

            assert!((d_threshold * 100 / ray_math::ray()) == 71, 2);

            lib::print(&d_threshold); 

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should calculate correct value with 1/2/5 collaterals
    public fun test_user_health_collateral_value() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            //1
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000);
            let value = logic::user_health_collateral_value(&clock,  &price_oracle, &mut stg,bob);
            lib::print(&value); 

            assert!(value == 18000_000000000, 2);

            //2
            logic::execute_deposit_for_testing<BTC_TEST>(&clock, &mut stg, 2, bob, 1_000000000);
            let value = logic::user_health_collateral_value(&clock,  &price_oracle, &mut stg,bob);
            assert!(value   == 45000_000000000, 2);

            //5
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, bob, 1000_000000000);
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, bob, 3000_000000000);
            logic::execute_deposit_for_testing<TEST_COIN>(&clock, &mut stg, 4, bob, 500000_000000000);
            // 25650 + 680 + 1800
            let value = logic::user_health_collateral_value(&clock, &price_oracle,&mut stg, bob);
            lib::print(&value); 

            assert!((value ) == 54000_000000000, 2);

            lib::print(&value); 

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should calculate correct value with 1/2/5 borrows
    public fun test_user_health_loan_value() {
        let alice = @0xace;
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            //1
            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, alice, 10000_000000000);
            logic::execute_deposit_for_testing<BTC_TEST>(&clock, &mut stg, 2, alice, 100000_000000000);
            logic::execute_deposit_for_testing<USDC_TEST>(&clock, &mut stg, 3, alice, 1000000_000000000);
            logic::execute_deposit_for_testing<TEST_COIN>(&clock, &mut stg, 4, alice, 10000000_000000000);
            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10000_000000000);

            logic::execute_borrow_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 1_000000000);

            let value = logic::user_health_loan_value(&clock,  &price_oracle, &mut stg,bob);
            lib::print(&value); 

            assert!(value == 1800_000000000, 2);

            //2
            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 1000_000000000);
            let value = logic::user_health_loan_value(&clock,  &price_oracle, &mut stg,bob);
            assert!(value   == 2800_000000000, 2);

            //5
            logic::execute_borrow_for_testing<BTC_TEST>(&clock, &price_oracle, &mut stg, 2, bob, 1_000000000);
            logic::execute_borrow_for_testing<USDC_TEST>(&clock, &price_oracle, &mut stg, 3, bob, 1000_000000000);
            logic::execute_borrow_for_testing<TEST_COIN>(&clock, &price_oracle, &mut stg, 4, bob, 100000_000000000);

            let value = logic::user_health_loan_value(&clock, &price_oracle,&mut stg, bob);
            lib::print(&value); 

            assert!((value ) == 31800_000000000, 2);

            lib::print(&value); 

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should return correct loan with user's balance
    public fun test_user_loan_value() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10000_000000000);

            logic::execute_borrow_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 1_000000000);

            let value = logic::user_loan_value(&clock,  &price_oracle, &mut stg,1,bob);
            lib::print(&value); 
            assert!(value == 1800_000000000,2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should reuturn correct collateral value with user's balance
    public fun test_user_collateral_value() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10000_000000000);

            logic::execute_borrow_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 1_000000000);

            let value = logic::user_collateral_value(&clock,  &price_oracle, &mut stg,1,bob);
            lib::print(&value); 
            assert!(value == 18000000_000000000,2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should reuturn correct collateral balance with user's balance
    public fun test_user_collateral_balance() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10000_000000000);

            logic::execute_borrow_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 1_000000000);

            let value = logic::user_collateral_balance( &mut stg,1,bob);
            lib::print(&value); 
            assert!(value == 10000_000000000,2);

            clock::increment_for_testing(&mut clock, 86400 * 1000 * 365 * 6);
            logic::update_state_of_all_for_testing(& clock, &mut stg);
            let value = logic::user_collateral_balance( &mut stg,1,bob);
            lib::print(&value); 
            assert!(value == 10000054021600,2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should return correct loan with user's balance
    public fun test_user_loan_balance() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10000_000000000);

            logic::execute_borrow_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 1_000000000);

            let value = logic::user_loan_balance( &mut stg,1,bob);
            lib::print(&value); 
            assert!(value == 1_000000000,2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        test_scenario::end(scenario);
    }

    #[test]
    // Should user borrow max
    // test to fix logic in borrow: assert!(health_factor > health_factor_in_borrow, error::user_is_unhealthy());
    public fun test_user_can_borrow_max() {
        let bob = @0xb0b;
        let scenario = test_scenario::begin(OWNER);
        sup_global::init_protocol(&mut scenario);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            let clock = clock::create_for_testing(ctx);
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, bob, 10000_000000000);

            logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 8000_000000000);

            let value = logic::user_loan_balance( &mut stg,0,bob);
            lib::print(&value); 
            assert!(value == 8000_000000000,2);

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(stg);
            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        test_scenario::end(scenario);
    }
}