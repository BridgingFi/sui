#[test_only]
#[allow(unused_mut_ref)]
module lending_core::pool_test {
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self};
    
    use lending_core::pool::{Self, Pool, PoolAdminCap};

    const OWNER: address = @0xA;

    #[test]
    public fun test_create_pool() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            let (balance_value, treasury_balance_value, decimal) = pool::get_pool_info(&pool);

            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 0, 0);
            assert!(decimal == 9, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    public fun test_deposit() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            let (balance_value, treasury_balance_value, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 0, 0);

            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(100, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            let (balance_value, _, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 100, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    public fun test_withdraw() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(100, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);

            let (balance_value, _, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 100, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);

            let ctx = test_scenario::ctx(&mut scenario);
            pool::withdraw_for_testing(&mut pool, 100, OWNER, ctx);

            let (balance_value, _, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 0, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&c) == 100, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    }

    #[test]
    public fun test_deposit_treasury() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(100, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);
            let (balance_value, _, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 100, 0);

            pool::deposit_treasury_for_testing(&mut pool, 100);
            let (balance_value, treasury_balance_value, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 100, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    public fun test_withdraw_treasury() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            
            let ctx = test_scenario::ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(100, ctx);
            pool::deposit_for_testing(&mut pool, coin, ctx);
            let (balance_value, _, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 100, 0);

            pool::deposit_treasury_for_testing(&mut pool, 100);
            let (balance_value, treasury_balance_value, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 100, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            let cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);

            pool::withdraw_treasury<SUI>(&mut cap, &mut pool, 100, OWNER, test_scenario::ctx(&mut scenario));
            let (_, treasury_balance_value, _) = pool::get_pool_info(&pool);
            assert!(treasury_balance_value == 0, 0);

            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            // check the owner's balance
            let c = test_scenario::take_from_sender<Coin<SUI>>(&scenario);
            assert!(coin::value(&c) == 100, 0);
            test_scenario::return_to_sender(&scenario, c);
        };

        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = 1506, location = lending_core::pool)]
    public fun test_withdraw_treasury_over_balance() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            let cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);

            pool::withdraw_treasury<SUI>(&mut cap, &mut pool, 100, OWNER, test_scenario::ctx(&mut scenario));

            test_scenario::return_shared(pool);
            test_scenario::return_to_sender(&scenario, cap);
        };

        test_scenario::end(scenario);
    }


    #[test]
    public fun test_get_coin_decimal() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::get_coin_decimal(&pool) == 9, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    public fun test_convert_amount() {
        assert!(pool::convert_amount(1000, 1, 2) == 10000, 0);
        assert!(pool::convert_amount(1000, 2, 1) == 100, 0);
    }

    #[test]
    public fun test_normal_amount() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::normal_amount(&pool, 1000000000) == 1000000000, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    public fun test_unnormal_amount() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::unnormal_amount(&pool, 1000000000) == 1000000000, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

}
