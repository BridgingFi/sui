#[test_only]
module volo_vault::init_vault;

// use lending_core::lending;
use sui::clock::Clock;
use sui::test_scenario::{Self, Scenario};
use volo_vault::init_lending;
use volo_vault::reward_manager;
use volo_vault::vault::{Self, Vault, AdminCap};
use volo_vault::vault_oracle;

#[test_only]
public fun init_vault(s: &mut Scenario, clock: &mut Clock) {
    let owner = s.sender();

    init_lending::init_protocol(s, clock);

    // Init vault
    s.next_tx(owner);
    {
        vault::init_for_testing(s.ctx());
    };

    // Init oracle
    s.next_tx(owner);
    {
        vault_oracle::init_for_testing(s.ctx());
    };

    // Create operator cap and transfer to owner
    s.next_tx(owner);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        let op_cap = vault::create_operator_cap(s.ctx());
        transfer::public_transfer(op_cap, owner);
        s.return_to_sender(admin_cap);
    };
}

#[test_only]
public fun init_create_vault<PrincipalCoinType>(s: &mut Scenario) {
    let owner = s.sender();

    // Create vault
    s.next_tx(owner);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        vault::create_vault<PrincipalCoinType>(&admin_cap, s.ctx());
        s.return_to_sender(admin_cap);
    };

    s.next_tx(owner);
    {
        let mut vault = s.take_shared<Vault<PrincipalCoinType>>();
        vault.set_deposit_fee(0);
        vault.set_withdraw_fee(0);
        vault.set_locking_time_for_withdraw(12 * 3600 * 1_000);
        vault.set_locking_time_for_cancel_request(0);
        test_scenario::return_shared(vault);
    };
}

#[test_only]
public fun init_create_reward_manager<PrincipalCoinType>(s: &mut Scenario) {
    let owner = s.sender();

    s.next_tx(owner);
    {
        let mut vault = s.take_shared<Vault<PrincipalCoinType>>();
        reward_manager::create_reward_manager<PrincipalCoinType>(&mut vault, s.ctx());
        test_scenario::return_shared(vault);
    };
}

// #[test_only]
// public fun init_navi_account_cap<PrincipalCoinType>(
//     s: &mut Scenario,
//     vault: &mut Vault<PrincipalCoinType>,
// ) {
//     let owner = s.sender();

//     s.next_tx(owner);
//     {
//         let navi_account_cap = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             0,
//             navi_account_cap,
//         );
//     }
// }
