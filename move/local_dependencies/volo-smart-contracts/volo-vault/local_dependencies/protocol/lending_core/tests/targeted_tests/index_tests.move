#[test_only]
module lending_core::index_test {
    use sui::coin::{Self};
    use sui::clock::{Self};
    use sui::test_scenario::{Self};

    use math::ray_math;
    use lending_core::lib;
    use lending_core::base;
    use lending_core::pool::{Self, Pool};
    use lending_core::sui_test::{SUI_TEST};
    use lending_core::usdc_test::{USDC_TEST};
    use lending_core::base_lending_tests::{Self};
    use oracle::oracle::{Self, PriceOracle, OracleAdminCap};
    use lending_core::storage::{Self, Storage};

    const Owner: address = @0x1;
    const UserA: address = @0xA;
    const UserB: address = @0xB;

    #[test]
    public fun test_update_state_logic() {
        let scenario = test_scenario::begin(Owner);
        let scenario_a = test_scenario::begin(UserA);
        let scenario_b = test_scenario::begin(UserB);
        let test_clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        clock::set_for_testing(&mut test_clock, 1704038400000);

        test_scenario::next_tx(&mut scenario, Owner);
        {
            // Init Protocol
            base::initial_protocol(&mut scenario, &test_clock);
        };

        test_scenario::next_tx(&mut scenario, Owner);
        {
            let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
            oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 1000);

            test_scenario::return_shared(price_oracle);
            test_scenario::return_to_sender(&scenario, oracle_admin_cap);
        };

        test_scenario::next_tx(&mut scenario_a, UserA);
        {
            // UserA Deposit 1m USDC
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario_a);
            let usdc_coin = coin::mint_for_testing<USDC_TEST>(1000000_000000, test_scenario::ctx(&mut scenario_a));
            let usdc_value = coin::value(&usdc_coin);
            base_lending_tests::base_deposit_for_testing(
                &mut scenario_a,
                &test_clock,
                &mut usdc_pool,
                usdc_coin,
                1,
                usdc_value
            );

            test_scenario::return_shared(usdc_pool);
        };

        test_scenario::next_tx(&mut scenario_b, UserB);
        {
            // UserB Deposit 1m Sui, Sui Price 0.5u
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario_b);
            let sui_coin = coin::mint_for_testing<SUI_TEST>(1000000_000000000, test_scenario::ctx(&mut scenario_b));
            let sui_value = coin::value(&sui_coin);
            base_lending_tests::base_deposit_for_testing(
                &mut scenario_b,
                &test_clock,
                &mut sui_pool,
                sui_coin,
                0,
                sui_value
            );

            test_scenario::return_shared(sui_pool);
        };

        test_scenario::next_tx(&mut scenario_b, UserB);
        {
            // UserB Borrow 200k USDC
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario_b);
            let borrow_value = 200000_000000;

            base_lending_tests::base_borrow_for_testing<USDC_TEST>(
                &mut scenario_b,
                &test_clock,
                &mut usdc_pool,
                1,
                borrow_value,
            );

            test_scenario::return_shared(usdc_pool);
        };

        test_scenario::next_tx(&mut scenario, Owner);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);

            lib::printf(b"Before UserB Repay");
            let (sui_supply_index, sui_borrow_index) = storage::get_index(&mut stg, 0);
            let usdc_treasury_balance = storage::get_treasury_balance(&stg, 1);
            let sui_treasury_balance = storage::get_treasury_balance(&stg, 0);
            let (usdc_supply_index, usdc_borrow_index) = storage::get_index(&mut stg, 1);
            let (sui_total_supply, sui_total_borrow) = storage::get_total_supply(&mut stg, 0);
            let (usdc_total_supply, usdc_total_borrow) = storage::get_total_supply(&mut stg, 1);
            let (sui_balance, sui_treasury_balance_pool, _) = pool::get_pool_info(&sui_pool);
            let (usdc_balance, usdc_treasury_balance_pool, _) = pool::get_pool_info(&usdc_pool);
            

            lib::print_u256(b"Sui Supply Index", sui_supply_index);
            lib::print_u256(b"Sui Borrow Index", sui_borrow_index);
            lib::print_u256(b"Sui Total Supply", sui_total_supply);
            lib::print_u256(b"Sui Total Borrow", sui_total_borrow);
            lib::print_u256(b"Sui Balance", (sui_balance as u256));
            lib::print_u256(b"Sui Treasury Balance(Pool)", (sui_treasury_balance_pool as u256));
            lib::print_u256(b"Sui Treasury Balance(Storage)", (sui_treasury_balance as u256));


            lib::print_u256(b"USDC Supply Index", usdc_supply_index);
            lib::print_u256(b"USDC Borrow Index", usdc_borrow_index);
            lib::print_u256(b"USDC Total Supply", usdc_total_supply);
            lib::print_u256(b"USDC Total Borrow", usdc_total_borrow);
            lib::print_u256(b"USDC Balance", (usdc_balance as u256));
            lib::print_u256(b"USDC Treasury Balance(Pool)", (usdc_treasury_balance_pool as u256));
            lib::print_u256(b"USDC Treasury Balance(Storage)", (usdc_treasury_balance as u256));

            test_scenario::return_shared(stg);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(usdc_pool);
        };

        clock::increment_for_testing(&mut test_clock, 60 * 60 * 24 * 10);

        test_scenario::next_tx(&mut scenario_b, UserB);
        {
            // UserB Repay 200k USDC
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario_b);

            // let usdc_coin = coin::mint_for_testing<USDC_TEST>(200000_140274, test_scenario::ctx(&mut scenario_b));
            let usdc_coin = coin::mint_for_testing<USDC_TEST>(200000_140274, test_scenario::ctx(&mut scenario_b));
            let usdc_value = coin::value(&usdc_coin);

            base_lending_tests::base_repay_for_testing<USDC_TEST>(
                &mut scenario_b,
                &test_clock,
                &mut usdc_pool,
                usdc_coin,
                1,
                usdc_value,
            );

            test_scenario::return_shared(usdc_pool);
        };

        test_scenario::next_tx(&mut scenario, Owner);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);

            lib::printf(b"After UserB Repay");
            let (sui_supply_index, sui_borrow_index) = storage::get_index(&mut stg, 0);
            let usdc_treasury_balance = storage::get_treasury_balance(&stg, 1);
            let sui_treasury_balance = storage::get_treasury_balance(&stg, 0);
            let (usdc_supply_index, usdc_borrow_index) = storage::get_index(&mut stg, 1);
            let (sui_total_supply, sui_total_borrow) = storage::get_total_supply(&mut stg, 0);
            let (usdc_total_supply, usdc_total_borrow) = storage::get_total_supply(&mut stg, 1);
            let (sui_balance, sui_treasury_balance_pool, _) = pool::get_pool_info(&sui_pool);
            let (usdc_balance, usdc_treasury_balance_pool, _) = pool::get_pool_info(&usdc_pool);

            lib::print_u256(b"Sui Supply Index", sui_supply_index);
            lib::print_u256(b"Sui Borrow Index", sui_borrow_index);
            lib::print_u256(b"Sui Total Supply", sui_total_supply);
            lib::print_u256(b"Sui Total Borrow", sui_total_borrow);
            lib::print_u256(b"Sui Balance", (sui_balance as u256));
            lib::print_u256(b"Sui Treasury Balance(Pool)", (sui_treasury_balance_pool as u256));
            lib::print_u256(b"Sui Treasury Balance(Storage)", (sui_treasury_balance as u256));

            lib::print_u256(b"USDC Supply Index", usdc_supply_index);
            lib::print_u256(b"USDC Borrow Index", usdc_borrow_index);
            lib::print_u256(b"USDC Total Supply", usdc_total_supply);
            lib::print_u256(b"USDC Total Borrow", usdc_total_borrow); // 0
            lib::print_u256(b"USDC Balance", (usdc_balance as u256));
            lib::print_u256(b"USDC Treasury Balance(Pool)", (usdc_treasury_balance_pool as u256));
            lib::print_u256(b"USDC Treasury Balance(Storage)", (usdc_treasury_balance as u256));

            lib::print_u256(b"UserB Should Repay The Total Debt", ray_math::ray_mul(200000_000000000, usdc_borrow_index));
            lib::print_u256(b"UserA Should Withdraw The Total Collateral", ray_math::ray_mul(1000000_000000000, usdc_supply_index));

            test_scenario::return_shared(stg);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(usdc_pool);
        };

        test_scenario::next_tx(&mut scenario_a, UserA);
        {
            // UserA Withdraw 1m USDC With Interest
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario_a);
            let usdc_value = 1000000_112219;
            base_lending_tests::base_withdraw_for_testing<USDC_TEST>(
                &mut scenario_a,
                &test_clock,
                &mut usdc_pool,
                1,
                usdc_value,
            );

            test_scenario::return_shared(usdc_pool);
        };

        test_scenario::next_tx(&mut scenario, Owner);
        {
            let stg = test_scenario::take_shared<Storage>(&scenario);
            let sui_pool = test_scenario::take_shared<Pool<SUI_TEST>>(&scenario);
            let usdc_pool = test_scenario::take_shared<Pool<USDC_TEST>>(&scenario);

            lib::printf(b"After UserA Withdraw");
            let (sui_supply_index, sui_borrow_index) = storage::get_index(&mut stg, 0);
            let usdc_treasury_balance = storage::get_treasury_balance(&stg, 1);
            let sui_treasury_balance = storage::get_treasury_balance(&stg, 0);
            let (usdc_supply_index, usdc_borrow_index) = storage::get_index(&mut stg, 1);
            let (sui_total_supply, sui_total_borrow) = storage::get_total_supply(&mut stg, 0);
            let (usdc_total_supply, usdc_total_borrow) = storage::get_total_supply(&mut stg, 1);
            let (sui_balance, sui_treasury_balance_pool, _) = pool::get_pool_info(&sui_pool);
            let (usdc_balance, usdc_treasury_balance_pool, _) = pool::get_pool_info(&usdc_pool);
            

            lib::print_u256(b"Sui Supply Index", sui_supply_index);
            lib::print_u256(b"Sui Borrow Index", sui_borrow_index);
            lib::print_u256(b"Sui Total Supply", sui_total_supply);
            lib::print_u256(b"Sui Total Borrow", sui_total_borrow);
            lib::print_u256(b"Sui Balance", (sui_balance as u256));
            lib::print_u256(b"Sui Treasury Balance(Pool)", (sui_treasury_balance_pool as u256));
            lib::print_u256(b"Sui Treasury Balance(Storage)", (sui_treasury_balance as u256));


            lib::print_u256(b"USDC Supply Index", usdc_supply_index);
            lib::print_u256(b"USDC Borrow Index", usdc_borrow_index);
            lib::print_u256(b"USDC Total Supply", usdc_total_supply);
            lib::print_u256(b"USDC Total Borrow", usdc_total_borrow);
            lib::print_u256(b"USDC Balance", (usdc_balance as u256));
            lib::print_u256(b"USDC Treasury Balance(Pool)", (usdc_treasury_balance_pool as u256));
            lib::print_u256(b"USDC Treasury Balance(Storage)", (usdc_treasury_balance as u256));

            lib::print_u256(b"Treasury Amount", ray_math::ray_mul(usdc_treasury_balance, usdc_supply_index));

            test_scenario::return_shared(stg);
            test_scenario::return_shared(sui_pool);
            test_scenario::return_shared(usdc_pool);
        };

        clock::destroy_for_testing(test_clock);
        test_scenario::end(scenario);
        test_scenario::end(scenario_a);
        test_scenario::end(scenario_b);
    }
}
