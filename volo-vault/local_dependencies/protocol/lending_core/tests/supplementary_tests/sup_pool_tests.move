#[test_only]
module lending_core::sup_pool_test {
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::test_scenario::{Self};
    use sui::transfer;

    use lending_core::pool::{Self, Pool, PoolAdminCap};

    const OWNER: address = @0xA;


    #[test]
    // Should create 2 pools with same coinType successfully
    public fun test_create_same_pool() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 9, test_scenario::ctx(&mut scenario));
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 10, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            let (balance_value, treasury_balance_value, decimal) = pool::get_pool_info(&pool);

            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 0, 0);
            assert!(decimal == 10, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should deposit successfully with matched cointype
    public fun test_deposit_balance() {
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

            pool::deposit_balance_for_testing(&mut pool, coin::into_balance(coin), OWNER);

            let (balance_value, _, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 100, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should withdraw successfully with balance
    public fun test_withdraw_balance() {
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
            let balance = pool::withdraw_balance_for_testing(&mut pool, 100, OWNER);
            let coin_i = coin::zero<SUI>(ctx);    
            coin::join( &mut coin_i, coin::from_balance(balance, ctx));
            transfer::public_transfer(coin_i, OWNER);

            // balance::join(OWNER.balance, balance);
            
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
    #[expected_failure(abort_code = 2, location=sui::balance)]
    // Should fail if withdraw amount over pool balance
    public fun test_withdraw_excess() {
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
            pool::withdraw_for_testing(&mut pool, 10000, OWNER, ctx);

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
    #[expected_failure(abort_code = 2, location=sui::balance)]
    // Should fail if withdraw amount over pool balance
    public fun test_withdraw_balance_excess() {
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
            let balance = pool::withdraw_balance_for_testing(&mut pool, 1000, OWNER);
            let coin_i = coin::zero<SUI>(ctx);    
            coin::join( &mut coin_i, coin::from_balance(balance, ctx));
            transfer::public_transfer(coin_i, OWNER);
            
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
    #[expected_failure(abort_code = 1506, location=lending_core::pool)]
    // Should fail if withdraw amount over pool balance
    public fun test_deposit_treasury_excess() {
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

            pool::deposit_treasury_for_testing(&mut pool, 101);
            let (balance_value, treasury_balance_value, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 100, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }
    

    #[test]
    #[expected_failure(abort_code = 1506, location=lending_core::pool)]
    // Should fail if withdraw amount over pool balance
    public fun test_withdraw_treasury_excess() {
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

            pool::deposit_treasury_for_testing(&mut pool, 101);
            let (balance_value, treasury_balance_value, _) = pool::get_pool_info(&pool);
            assert!(balance_value == 0, 0);
            assert!(treasury_balance_value == 100, 0);

            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }
    

    #[test]
    // Should convert successfully if cur_decimal = 0
    // Should convert successfully if target_decimal = 0
    // Should convert successfully if cur_decimal = 0 and target = 20
    public fun test_convert_amount_sup() {
        assert!(pool::convert_amount(1000, 0, 2) == 100000, 0);
        assert!(pool::convert_amount(1000, 2, 0) == 10, 0);
        // Not Pass
        // assert!(pool::convert_amount(1000, 0, 20) == 100000000000000000000000, 0);
    }

    #[test]
    // Should normal successfully with cur decimal of 1 and 18
    public fun test_normal_amount_sup() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 1, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::normal_amount(&pool, 1) == 100000000, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 18, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::normal_amount(&pool, 1000000000000000000) == 1000000000, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }

    #[test]
    // Should unnormal successfully with cur decimal of 1 and 18
    public fun test_unnormal_amount_sup() {
        let scenario = test_scenario::begin(OWNER);
        {
            pool::init_for_testing(test_scenario::ctx(&mut scenario));
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 1, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::unnormal_amount(&pool, 1000000000) == 10, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool_admin_cap = test_scenario::take_from_sender<PoolAdminCap>(&scenario);
            pool::create_pool_for_testing<SUI>(&pool_admin_cap, 18, test_scenario::ctx(&mut scenario));

            test_scenario::return_to_sender(&scenario, pool_admin_cap);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            let pool = test_scenario::take_shared<Pool<SUI>>(&scenario);
            assert!(pool::unnormal_amount(&pool, 1000000000) == 1000000000000000000, 0);
            test_scenario::return_shared(pool);
        };

        test_scenario::end(scenario);
    }


// ---
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
    #[expected_failure(abort_code = 1506, location=lending_core::pool)]
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
