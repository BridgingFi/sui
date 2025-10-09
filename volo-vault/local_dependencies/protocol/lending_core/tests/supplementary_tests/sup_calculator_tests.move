#[test_only]
module lending_core::sup_calculator_tests {
    use sui::clock;
    use sui::test_scenario::{Self};

    use math::ray_math;
    use oracle::oracle::{PriceOracle};
    use sui::coin::{Self};
    use oracle::oracle::{Self, OracleFeederCap};

    use lending_core::global;
    use lending_core::calculator;
    use std::vector;
    use lending_core::pool::{Pool};

    use lending_core::sui_test::{SUI_TEST};
    use lending_core::usdc_test::{USDC_TEST};
    use lending_core::base_lending_tests::{Self};
    use lending_core::base::{Self};
    use lending_core::storage::{Storage};


    const SUI_OPT_UTIL:u256 = 550000000000000000000000000;
    const SUI_MUL:u256 = 116360000000000000000000000;
    const SUI_BASE_RATE:u256 = 0;
    const SUI_JUMP_MUL:u256 = 3000000000000000000000000000;
    const SUI_RESERVE_F:u256 = 200000000000000000000000000;

    const OWNER: address = @0xA;

    

    #[test]
    // Should caculate_utilization return correct value with valid asset
    public fun test_caculate_utilization_valid() {
        let scenario = test_scenario::begin(OWNER);
        let _clock= clock::create_for_testing(test_scenario::ctx(&mut scenario));
        base::initial_protocol(&mut scenario, &_clock);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let sui_coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));
            base_lending_tests::base_deposit_for_testing(
                &mut scenario,
                &_clock,
                &mut pool,
                sui_coin,
                0,
                100_000000000
            );            
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(&mut scenario, OWNER); 
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            base_lending_tests::base_borrow_for_testing<SUI_TEST>(
                &mut scenario,
                &_clock,
                &mut pool,
                0,
                10_000000000,
            );
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let c = calculator::caculate_utilization(&mut stg, 0);
            std::debug::print(&c);
            assert!(c == ray_math::ray() / 10, 1);
            test_scenario::return_shared(stg);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = 1, location=sui::dynamic_field)]
    // Should caculate_utilization return correct value with invalid asset
    public fun test_caculate_utilization_invalid() {
        let scenario = test_scenario::begin(OWNER);
        let _clock= clock::create_for_testing(test_scenario::ctx(&mut scenario));
        base::initial_protocol(&mut scenario, &_clock);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let c = calculator::caculate_utilization(&mut stg, 10);
            std::debug::print(&c);
            assert!(c == ray_math::ray() / 10, 1);
            test_scenario::return_shared(stg);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test]
    // Should caculate_utilization return correct value when borrow amount is 0
    public fun test_caculate_utilization_zero() {
        let scenario = test_scenario::begin(OWNER);
        let _clock= clock::create_for_testing(test_scenario::ctx(&mut scenario));
        base::initial_protocol(&mut scenario, &_clock);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let c = calculator::caculate_utilization(&mut stg, 0);
            std::debug::print(&c);
            assert!(c == 0, 1);
            test_scenario::return_shared(stg);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test]
    // Should calculate_borrow_rate return correct value under optimal_utilization
    // Should calculate_supply_rate return correct value with 10% ray borrow rate
    public fun test_borrow_rate_under_opt() {
        let scenario = test_scenario::begin(OWNER);
        let _clock= clock::create_for_testing(test_scenario::ctx(&mut scenario));
        base::initial_protocol(&mut scenario, &_clock);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let sui_coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));
            base_lending_tests::base_deposit_for_testing(
                &mut scenario,
                &_clock,
                &mut pool,
                sui_coin,
                0,
                100_000000000
            );            
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(&mut scenario, OWNER); 
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            base_lending_tests::base_borrow_for_testing<SUI_TEST>(
                &mut scenario,
                &_clock,
                &mut pool,
                0,
                10_000000000,
            );
            test_scenario::return_shared(pool);
        };

        // test borrow rate
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let b = calculator::calculate_borrow_rate(&mut stg, 0);
            let u = calculator::caculate_utilization(&mut stg, 0);
            std::debug::print(&b);
            assert!(b == ray_math::ray_mul(u, SUI_MUL + SUI_BASE_RATE), 1);
            test_scenario::return_shared(stg);
        };

        // test supply rate
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let b = calculator::calculate_borrow_rate(&mut stg, 0);
            let u = calculator::caculate_utilization(&mut stg, 0);
            let s =  calculator::calculate_supply_rate(&mut stg, 0, b);
            let supply_rate = ray_math::ray_mul(
                ray_math::ray_mul(b, u),
                ray_math::ray() - SUI_RESERVE_F
            );
            assert!(s == supply_rate, 1);
            test_scenario::return_shared(stg);
        };
        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test]
    // Should calculate_borrow_rate return correct value over optimal_utilization
    // Should calculate_supply_rate return correct value with 95% ray borrow rate
    public fun test_borrow_rate_over_opt() {
        let scenario = test_scenario::begin(OWNER);
        let _clock= clock::create_for_testing(test_scenario::ctx(&mut scenario));
        base::initial_protocol(&mut scenario, &_clock);

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let sui_coin = coin::mint_for_testing<SUI_TEST>(100_000000000, test_scenario::ctx(&mut scenario));
            base_lending_tests::base_deposit_for_testing(
                &mut scenario,
                &_clock,
                &mut pool,
                sui_coin,
                0,
                100_000000000
            );            
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);
            let usdc_coin = coin::mint_for_testing<USDC_TEST>(1000_000000000, test_scenario::ctx(&mut scenario));
            base_lending_tests::base_deposit_for_testing(
                &mut scenario,
                &_clock,
                &mut pool,
                usdc_coin,
                1,
                1000_000000000
            );            
            test_scenario::return_shared(pool)
        };

        test_scenario::next_tx(&mut scenario, OWNER); 
        {
            let pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            base_lending_tests::base_borrow_for_testing<SUI_TEST>(
                &mut scenario,
                &_clock,
                &mut pool,
                0,
                90_000000000,
            );
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let b = calculator::calculate_borrow_rate(&mut stg, 0);
            let u = calculator::caculate_utilization(&mut stg, 0);
            std::debug::print(&b);
            let borrow_rate = ray_math::ray_mul(SUI_OPT_UTIL, SUI_MUL) 
                                    + ray_math::ray_mul((u - SUI_OPT_UTIL), SUI_JUMP_MUL);
            assert!(b == borrow_rate, 1);
            test_scenario::return_shared(stg);
        };

        // test supply rate
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let b = calculator::calculate_borrow_rate(&mut stg, 0);
            let u = calculator::caculate_utilization(&mut stg, 0);
            let s =  calculator::calculate_supply_rate(&mut stg, 0, b);
            let supply_rate = ray_math::ray_mul(
                ray_math::ray_mul(b, u),
                ray_math::ray() - SUI_RESERVE_F
            );
            assert!(s == supply_rate, 1);
            test_scenario::return_shared(stg);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
    }

    #[test]
    // Should calculate_linear_interest return correct value with 0/0.5/5 ray rate
     public fun test_calculate_compounded_interest_ratess() {
        let rates = vector::empty<u256>();

        vector::push_back(&mut rates, 0);
        vector::push_back(&mut rates, ray_math::ray());
        vector::push_back(&mut rates, ray_math::ray() / 2);

        let i = vector::length(&rates);
        while (i > 0) {
            let timestamp_diff = 3600;
            let rate =  *vector::borrow(&rates, i - 1);
            let exp_minus_one = timestamp_diff - 1;
            let exp_minus_two = timestamp_diff - 2;
            let rate_per_sec = rate / (60 * 60 * 24 * 365);
            let base_power_two = ray_math::ray_mul(rate_per_sec, rate_per_sec);
            let base_power_three = ray_math::ray_mul(base_power_two, rate_per_sec);

            let second_term = timestamp_diff * exp_minus_one * base_power_two / 2;
            let third_term = timestamp_diff * exp_minus_one * exp_minus_two * base_power_three / 6;
            let expect_result = ray_math::ray() + rate_per_sec * timestamp_diff + second_term + third_term;

            let result = calculator::calculate_compounded_interest(
                timestamp_diff,
                rate
            );
            assert!(result == expect_result, 0);
            i = i - 1;
        };
    }

    #[test]
    #[expected_failure(abort_code = 6011, location=oracle::oracle)]
    // Should calculate_value return correctly with invalid oracle id
    public fun test_calculate_value_invalid() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        // calculate token value
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            // 10 * 1800_000000000 / 10**9
            let _ = calculator::calculate_value(
                &clock,
                &price_oracle,
                10,
                20
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 6011, location=oracle::oracle)]
    // Should calculate_amount return correctly with invalid oracle id
    public fun test_calculate_amount_invalid() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        // calculate token amount
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            // 18000 * 10**9 / 1800_000000000
            let _ = calculator::calculate_amount(
                &clock,
                &price_oracle,
                18000,
                20
            );

            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1502, location=lending_core::calculator)]
    // Should calculate_amount return correctly with 0 price
    public fun test_calculate_value() {
        let scenario = test_scenario::begin(OWNER);
        {
            global::init_protocol(&mut scenario);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let oracle_id = 1;
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);

            oracle::update_token_price(
                &oracle_feeder_cap,
                &clock,
                &mut price_oracle,
                oracle_id,
                0,
            );
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle); 
            test_scenario::return_to_sender(&scenario, oracle_feeder_cap);
        };
        // calculate token value
        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            let clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));

            let value = calculator::calculate_value(
                &clock,
                &price_oracle,
                10,
                1
            );
            assert!(value == 0, 1);
            clock::destroy_for_testing(clock);
            test_scenario::return_shared(price_oracle);
        };

        test_scenario::end(scenario);
    }
}
