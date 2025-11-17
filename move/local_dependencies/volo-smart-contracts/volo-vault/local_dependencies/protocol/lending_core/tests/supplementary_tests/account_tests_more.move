#[test_only]
module lending_core::account_test_more {
    use sui::clock;
    use sui::test_scenario::{Self, Scenario};
    use sui::transfer;

    use lending_core::base;
    use lending_core::lending::{Self};
    
    const OWNER: address = @0xA;
    const OWNER2: address = @0xA;
    
    #[test_only]
    public fun create_account_cap_for_testing(scenario: &mut Scenario) {
        let cap = lending::create_account(test_scenario::ctx(scenario));
        transfer::public_transfer(cap, test_scenario::sender(scenario))
    }

    //Should create_account_cap successfully create an AccountCap with a valid UID and owner.
    #[test]
    public fun test_create_account_cap() {
        let scenario = test_scenario::begin(OWNER);
        let scenario2 = test_scenario::begin(OWNER2);
        let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
        {
            base::initial_protocol(&mut scenario, &_clock);
        };

        test_scenario::next_tx(&mut scenario, OWNER);
        {
            create_account_cap_for_testing(&mut scenario);
        };

        clock::destroy_for_testing(_clock);
        test_scenario::end(scenario);
        test_scenario::end(scenario2);
    }

    // Should create_child_account_cap successfully create a child account with the same owner as the parent account.
    // #[test]
    // public fun test_create_child_account_cap() {
    //     let scenario = test_scenario::begin(OWNER);
    //     let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    //     {
    //         base::initial_protocol(&mut scenario, &_clock);
    //     };

    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         create_account_cap_for_testing(&mut scenario);
    //     };

    //     // Initialize test scenario for the parent account
    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         // Create a parent account cap
    //         let account_cap = test_scenario::take_from_sender<AccountCap>(&scenario);
    //         let child_cap = lending::create_child_account(&account_cap, test_scenario::ctx(&mut scenario));
            
    //         transfer::public_transfer(child_cap, test_scenario::sender(&scenario));
    //         test_scenario::return_to_sender(&scenario, account_cap);
    //     };

    //     // Clean up and end the test scenario
    //     clock::destroy_for_testing(_clock);
    //     test_scenario::end(scenario);
    // }

    // Should delete_account_cap properly delete an account.
    // #[test]
    // public fun test_delete_account_cap() {
    //     let scenario = test_scenario::begin(OWNER);
    //     let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    //     {
    //         base::initial_protocol(&mut scenario, &_clock);
    //     };

    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         create_account_cap_for_testing(&mut scenario);
    //     };

    //     // Initialize test scenario for the parent account
    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         // Create a parent account cap
    //         let account_cap = test_scenario::take_from_sender<AccountCap>(&scenario);
    //         lending::delete_account(account_cap);

    //     };

    //     // Clean up and end the test scenario
    //     clock::destroy_for_testing(_clock);
    //     test_scenario::end(scenario);
    // }

    // Should delete child_account_cap 
    // #[test]
    // public fun test_delete_child_account_cap() {
    //     let scenario = test_scenario::begin(OWNER);
    //     let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    //     {
    //         base::initial_protocol(&mut scenario, &_clock);
    //     };

    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         create_account_cap_for_testing(&mut scenario);
    //     };

    //     // Initialize test scenario for the parent account
    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         // Create a parent account cap
    //         let account_cap = test_scenario::take_from_sender<AccountCap>(&scenario);
    //         let child_cap = account::create_child_account(&account_cap, test_scenario::ctx(&mut scenario));

    //         lending::delete_account(child_cap);
    //         lending::delete_account(account_cap);
    //     };

    //     // Clean up and end the test scenario
    //     clock::destroy_for_testing(_clock);
    //     test_scenario::end(scenario);
    // }
    
    //Should account_owner return the correct owner of an account cap and child cap.
    // #[test]
    // public fun test_return_correct_address() {
    //     let scenario = test_scenario::begin(OWNER);
    //     let _clock = clock::create_for_testing(test_scenario::ctx(&mut scenario));
    //     {
    //         base::initial_protocol(&mut scenario, &_clock);
    //     };

    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         create_account_cap_for_testing(&mut scenario);
    //     };

    //     // Initialize test scenario for the parent account
    //     test_scenario::next_tx(&mut scenario, OWNER);
    //     {
    //         // Create a parent account cap
    //         let account_cap = test_scenario::take_from_sender<AccountCap>(&scenario);
    //         let account_owner = account::account_owner(&account_cap);

    //         let child_cap = lending::create_child_account(&account_cap, test_scenario::ctx(&mut scenario));
    //         let child_owner = account::account_owner(&child_cap);

    //         assert!(account_owner == child_owner, 0);

    //         transfer::public_transfer(child_cap, test_scenario::sender(&scenario));
    //         test_scenario::return_to_sender(&scenario, account_cap);
    //     };

    //     // Clean up and end the test scenario
    //     clock::destroy_for_testing(_clock);
    //     test_scenario::end(scenario);
    // }

}
