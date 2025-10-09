// #[test_only]
// /*
//     This testing module is to test the upgrade of the patch pr update_state.
//     Please copy the following update_state_for_testing_deprecated function,
//     paste it to logic.move and uncomment this file to enable testing.
// */
// module lending_core::patch_update_state_balance_tests {
//     use std::vector;
//     use sui::clock;
//     use sui::test_scenario::{Self};

//     use math::ray_math;
//     use oracle::oracle::{PriceOracle, OracleFeederCap, OracleAdminCap, Self};
//     use lending_core::sup_global;
//     use lending_core::sup_edge_global;

//     use lending_core::logic::{Self};
//     use lending_core::btc_test::{BTC_TEST};
//     use lending_core::eth_test::{ETH_TEST};
//     use lending_core::usdt_test::{USDT_TEST};
//     use lending_core::usdc_test::{USDC_TEST};
//     use lending_core::test_coin::{TEST_COIN};
//     use lending_core::storage::{Self, Storage};
//     use lending_core::lib;
//     use lending_core::calculator;


//     // #[test_only]
//     // public fun update_state_for_testing_deprecated(clock: &Clock, storage: &mut Storage, asset: u8) {
//     //     let current_timestamp = clock::timestamp_ms(clock);

//     //     let last_update_timestamp = storage::get_last_update_timestamp(storage, asset);
//     //     let timestamp_difference = (current_timestamp - last_update_timestamp as u256) / 1000; 
//     //     let (current_supply_index, current_borrow_index) = storage::get_index(storage, asset); 
//     //     let (current_supply_rate, current_borrow_rate) = storage::get_current_rate(storage, asset); 

//     //     let linear_interest = calculator::calculate_linear_interest(timestamp_difference, current_supply_rate);
//     //     let new_supply_index = ray_math::ray_mul(linear_interest, current_supply_index);

//     //     let compounded_interest = calculator::calculate_compounded_interest(timestamp_difference, current_borrow_rate);
//     //     let new_borrow_index = ray_math::ray_mul(compounded_interest, current_borrow_index);

//     //     let (_, _, _, reserve_factor, _) = storage::get_borrow_rate_factors(storage, asset);
        
//     //     let (total_supply, total_borrow) = storage::get_total_supply(storage, asset);

//     //     let interest_on_borrow = ray_math::ray_mul(total_borrow, (new_borrow_index - current_borrow_index));
//     //     let interest_on_supply = ray_math::ray_mul(total_supply, (new_supply_index - current_supply_index));

//     //     let scaled_borrow_amount = ray_math::ray_div(interest_on_borrow, new_borrow_index);
//     //     let scaled_supply_amount = ray_math::ray_div(interest_on_supply, new_supply_index);

//     //     let reserve_amount = ray_math::ray_mul(
//     //         ray_math::ray_mul(total_borrow, (new_borrow_index - current_borrow_index)),
//     //         reserve_factor
//     //     );
//     //     let scaled_reserve_amount = ray_math::ray_div(reserve_amount, new_borrow_index);

//     //     storage::update_state(storage, asset, new_borrow_index, new_supply_index, current_timestamp, scaled_reserve_amount);
//     //     storage::increase_balance_for_pool(storage, asset, scaled_supply_amount, scaled_borrow_amount + scaled_reserve_amount)
//     // }

//     const OWNER: address = @0xA;
//     #[test]
//     /*
//         In old contract
//         1. A deposits ETH and USDT, B deposits USDT 
//         2. B borrows maximum USDT
//         3. 1 year past
//         4. upgrade contract 
//         5. B repays half debt and withdraw a part of USDT
//         6. 1 year past
//         7. B repays all debt and withdraw all USDT
//         8. A withdraw all ETH and USDT
//         9. Should calculate correctly for interests, balances, indices, treasury, etc. 
//     */
//     public fun test_update_state_upgrade_1 () {
//         let alice = @0xace;
//         let bob = @0xb0b;
//         let scenario = test_scenario::begin(OWNER);

//         sup_global::init_protocol(&mut scenario);

//         test_scenario::next_tx(&mut scenario, OWNER);
//         {
//             //init
//             let ctx = test_scenario::ctx(&mut scenario);
//             let clock = clock::create_for_testing(ctx);
//             let stg = test_scenario::take_shared<Storage>(&scenario);
//             let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
//             let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
            
//             oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000000);

//             // A deposits 10000U and 10ETH
//             logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
//             logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, alice, 10_000000000);

//             // B deposits 10ETH
//             logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000); 

//             // B borrows 9000U
//             logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle,&mut stg, 0, bob, 9000_000000000); 

//             // 1 year past
//             clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
//             logic::update_state_for_testing_deprecated(&clock, &mut stg, 0);

//             lib::printf(b"past one year");
//             // upgrade contract
//             // simulate upgrade... 

//             // repays half debt and withdraw a part of USDT
//             let (s, b) = storage::get_total_supply(&mut stg, 0);
//             let usdt_excess_s = s - 10000_000000000; 
//             let usdt_excess_b = b - 9000_000000000; 
//             lib::printf(b"usdt balance");
//             lib::print(&s);
//             lib::print(&b);

//             // issue occurs
//             assert!(usdt_excess_s > 0, 1);
//             assert!(usdt_excess_b > 0, 1);

//             let (s, b) = storage::get_total_supply(&mut stg, 1);
//             let eth_excess_s = s - 20_000000000; 
//             let eth_excess_b = b;
//             lib::printf(b"eth balance");
//             lib::print(&s);
//             lib::print(&b);
//             assert!(eth_excess_b == 0 && eth_excess_s == 0, 0);

//             let ( _,b_before_repay_1) = storage::get_total_supply(&mut stg, 0);

//             // B repays half debt and withdraw a part of ETH, 3ETH
//             logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 4500_000000000);
//             logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 3_000000000);
//             lib::printf(b"repay 4500U");

//             lib::printf(b"usdt balance");
//             let (s, b) = storage::get_total_supply(&mut stg, 0);
//             lib::print(&s);
//             lib::print(&b);
//             // borrow index ~= 1.16
//             let reduced_balance = (b_before_repay_1 - b) / 116 * 100 / 1000000000;
//             // assert!(reduced_balance > 4450 && reduced_balance < 4500, 0);
//             lib::print_index(&mut stg, 0); // 1124713000000000000000000000 1160649354904960155468616000

//             // 1 year past
//             lib::printf(b"1 year past");
//             clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
//             logic::update_state_for_testing(&clock, &mut stg, 0);
//             lib::print_index(&mut stg, 0); // 1143522323274727658791101533 1195979692193174820436870454

//             // B repays all debt and withdraw all USDT

//             // repays 6000, total debt ~= (9000 - 4500 / 1.16) * 1.196 = 6124
//             let excess = logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 6130_000000000);
//             let amount = logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 10_000000000);
//             lib::print(&amount);
//             let (_, b) = storage::get_user_balance(&mut stg, 0, bob);
//             lib::print(&s); // 11108842878139
//             lib::print(&b); // 6455780507881
//             assert!(b == 0, 0);
//             assert!(excess < 10_000000000, 0);
//             assert!(amount == 7_000000000, 0); 

//             //  7. A withdraw all ETH and USDT
//             // error: cannot withdraw because scale_supply_balance >= scale_borrow_balance + amount
//             lib::printf(b"A withdraws all");

//             // amount = 10000 * 1.143522323274727658791101533
//             // let amount_u = logic::execute_withdraw_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, alice, 11435_223232747);
//             let amount_e = logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, alice, 10_000000000);

//             let (s, b) = storage::get_user_balance(&mut stg, 0, alice);
//             assert!(s == 10000_000000000, 0);
//             let (s, b) = storage::get_user_balance(&mut stg, 1, alice);
//             assert!(s == 0, 0);

//             let (s, b) = storage::get_total_supply(&mut stg, 0);
//             // treasury = 6455.780507881 * (1.195979 - 1.1606) * 0.07 / 1.14352~= 14
//             lib::print(&(s - 10000_000000000 - usdt_excess_s));
//             lib::close_to(usdt_excess_s, s - 10000_000000000 - 14_000000000, 0);
//             assert!(usdt_excess_b == b, 0);

//             let (s, b) = storage::get_total_supply(&mut stg, 1);
//             assert!(s == 0, 0);
//             assert!(b == 0, 0);

//             clock::destroy_for_testing(clock);
//             test_scenario::return_shared(stg);
//             test_scenario::return_shared(price_oracle);
//             test_scenario::return_to_sender(&scenario, oracle_admin_cap);
//         };
//         test_scenario::end(scenario);
//     }

//     /*
//         In old contract
//         1. A deposits ETH and USDT, B deposits USDT 
//         2. B borrows 4000 USDT
//         3. 1 year past
//         4. upgrade contract 
//         5. B deposits 10 ETH and borrows 1000 USDT
//         6. C deposits 10 ETH and borrows 2000 USDT
//         7. 1 year past
//         8. 1 year past
//         9  C repays and withdraws all, B repays all
//         10. A, B withdraw all
//     */
//     // Should not affect current treasury balance before upgrade
//     #[test]
//     public fun test_update_state_upgrade_2 () {
//         let alice = @0xace;
//         let bob = @0xb0b;
//         let chad = @0xcad;
//         let scenario = test_scenario::begin(OWNER);

//         sup_global::init_protocol(&mut scenario);

//         test_scenario::next_tx(&mut scenario, OWNER);
//         {
//             //init
//             let ctx = test_scenario::ctx(&mut scenario);
//             let clock = clock::create_for_testing(ctx);
//             let stg = test_scenario::take_shared<Storage>(&scenario);
//             let price_oracle = test_scenario::take_shared<PriceOracle>(&scenario);
//             let oracle_admin_cap = test_scenario::take_from_sender<OracleAdminCap>(&scenario);
//             let oracle_feeder_cap = test_scenario::take_from_sender<OracleFeederCap>(&scenario);
            
//             oracle::set_update_interval(&oracle_admin_cap, &mut price_oracle, 60 * 60 * 24 * 10000000);

//             // A deposits 10000U and 10ETH
//             logic::execute_deposit_for_testing<USDT_TEST>(&clock, &mut stg, 0, alice, 10000_000000000);
//             logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, alice, 10_000000000);

//             // B deposits 10ETH
//             logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, bob, 10_000000000); 

//             // B borrows 4000U
//             logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle,&mut stg, 0, bob, 4000_000000000); 

//             // 1 year past
//             clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
//             logic::update_state_for_testing_deprecated(&clock, &mut stg, 0);

//             lib::printf(b"past one year");

//             // upgrade contract
//             // simulate upgrade... 

//             let (s, b) = storage::get_total_supply(&mut stg, 0);
//             let usdt_excess_s = s - 10000_000000000; 
//             let usdt_excess_b = b - 4000_000000000; 

//             // issue occurs
//             assert!(usdt_excess_s > 0, 1);
//             assert!(usdt_excess_b > 0, 1);

//             // B deposits more ETH and borrow more USDT
//             logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, alice, 10_000000000);
//             logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle,&mut stg, 0, bob, 1000_000000000); 

//             // C deposits more ETH and borrow more USDT
//             logic::execute_deposit_for_testing<ETH_TEST>(&clock, &mut stg, 1, chad, 10_000000000);
//             logic::execute_borrow_for_testing<USDT_TEST>(&clock, &price_oracle,&mut stg, 0, chad, 2000_000000000); 

//             let (s, b) = storage::get_total_supply(&mut stg, 1);
//             let eth_excess_s = s - 40_000000000; 
//             let eth_excess_b = b;
//             assert!(eth_excess_b == 0 && eth_excess_s == 0, 0);

//             lib::printf(b"data before T2");
//             lib::print_index(&mut stg, 0); // 1007440000000000000000000000 1020199999993627485825496000
//             lib::print_balance(&mut stg, 0); // 10073850551894 7025344050178

//             let (usdt_index_before, usdt_borrow_before) = storage::get_index(&mut stg, 0);

//             // 1 year past
//             clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
//             logic::update_state_for_testing(&clock, &mut stg, 0);

//             let (usdt_index_before, usdt_borrow_before) = storage::get_index(&mut stg, 0);
//             lib::printf(b"data after T2");
//             lib::print_index(&mut stg, 0); // 1030804074849179632282928318 1056865487973271434610819789 
//             lib::print_balance(&mut stg, 0); // 10091342854445 7025344050178

//             // 1 year past
//             clock::increment_for_testing(&mut clock, 86400 * 365 * 1000);
//             logic::update_state_for_testing(&clock, &mut stg, 0);

//             let (usdt_index_before, usdt_borrow_before) = storage::get_index(&mut stg, 0);
//             lib::printf(b"data after T3");
//             lib::print_index(&mut stg, 0); // 1054709998338038122122642450 1094848715620425491425986443 
//             lib::print_balance(&mut stg, 0); // 10109053094221 7025344050178
//             // treasury_balance at T2 = 7025.344 * (1.0948 - 1.0567) * 0.07 / 1.0308 = 18.17
//             lib::close_to(10109053094221 - 10091342854445, 18_000000000, 0);

//             // C repays and withdraws all

//             // C gets liquidated due to price drop
//             oracle::update_token_price(
//                 &oracle_feeder_cap,
//                 &clock,
//                 &mut price_oracle,
//                 1,
//                 250_000000000,
//             ); 

//             // liquidate 100U
//             let (bonus_balance, excess_amount, treasury_reserved_collateral_balance)  = logic::execute_liquidate_for_testing<USDT_TEST, ETH_TEST>(&clock, &price_oracle, &mut stg, chad, 1, 0, 100_000000000);

//             // 2000 / 1.0202 * 1.094848 - 100 ~= 2046.3
//             let excess = logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, chad, 2047_000000000);
//             lib::print(&excess);
//             let amount = logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, chad, 10_000000000);
//             let (_, b) = storage::get_user_balance(&mut stg, 0, chad);
//             assert!(b == 0, 0);
//             lib::close_to(excess, 0, 0);
//             // 10 - (100 / 250) * 1.05 = 9.58
//             assert!(amount == 9_580000000, 0); 

//             // B repays all

//             // (4000 / 1 + 1000 / 1.0202) * 1.094848 ~= 5452.5
//             let excess = logic::execute_repay_for_testing<USDT_TEST>(&clock, &price_oracle, &mut stg, 0, bob, 5453_000000000);
//             let (_, b) = storage::get_user_balance(&mut stg, 0, bob);
//             assert!(b == 0, 0);
//             lib::close_to(excess, 0, 0);

//             // A, B withdraw all

//             //ETH
//             logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, alice, 10_000000000);
//             logic::execute_withdraw_for_testing<ETH_TEST>(&clock, &price_oracle, &mut stg, 1, bob, 10_000000000);
//             let (s, b) = storage::get_total_supply(&mut stg, 1);
//             assert!(s == 10_000000000, 0);
//             assert!(b == 0, 0);


//             //USDT
//             // error: cannot withdraw because scale_supply_balance >= scale_borrow_balance + amount
//             let (s, b) = storage::get_total_supply(&mut stg, 0);
//             // (1.05686 - 10.2012) * 0.07
//             // treasury_balance at T2 = 7025.344 * (1.0568 - 1.0202) * 0.07 / 1.0308
//             // treasury_balance at T3 = 7025.344 * (1.0948 - 1.0567) * 0.07 / 1.0308
//             // sum_treasury = 7025.344 * (1.0948 - 1.0202) * 0.07 / 1.0308 = 35.59
//             lib::close_to(usdt_excess_s, s - 10000_000000000 - 35_590000000, 0);
//             assert!(usdt_excess_b == b, 0);  

//             clock::destroy_for_testing(clock);
//             test_scenario::return_shared(stg);
//             test_scenario::return_shared(price_oracle);
//             test_scenario::return_to_sender(&scenario, oracle_admin_cap);
//             test_scenario::return_to_sender(&scenario, oracle_feeder_cap);

//         };
//         test_scenario::end(scenario);
//     }
// }