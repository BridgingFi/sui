#[test_only]
module bridgingfi_vault::vault_proxy_test;

use sui::clock;
use sui::coin::{Self, Coin};
use sui::test_scenario;

use bridgingfi_vault::vault_proxy;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::receipt::Receipt;
use volo_vault::reward_manager::RewardManager;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault;
use volo_vault::vault::{Vault, Operation, OperatorCap};
use volo_vault::vault_oracle::OracleConfig;

const OWNER: address = @0xa;
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000u256;

#[test]
// Happy path – wrapping a fresh deposit should enqueue the Volo request and return leftover coins.
public fun deposit_new_receipt_forwards_to_volo() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

    let expected_shares: u256 = 2_000_000_000u256;

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();
        let coin = coin::mint_for_testing<USDC_TEST_COIN>(2_000_000_000, s.ctx());

        let request_id = vault_proxy::deposit_new_receipt<USDC_TEST_COIN>(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            &clock,
            s.ctx(),
        );

        assert!(request_id == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let deposit_request = vault.deposit_request(0);
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == expected_shares);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(vault.deposit_id_count() == 1);

        let remaining_coin = s.take_from_sender<Coin<USDC_TEST_COIN>>();
        assert!(remaining_coin.value() == 1_000_000_000);

        s.return_to_sender(remaining_coin);
        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// The wrapper should surface Volo's pending-receipt guard instead of silently accepting a top-up.
#[expected_failure(abort_code = 5017, location = volo_vault::vault)]
public fun deposit_with_receipt_rejects_pending_status() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

    let first_expected_shares: u256 = 2_000_000_000u256;

    // Bootstrap an initial deposit to mint a receipt.
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();
        let coin = coin::mint_for_testing<USDC_TEST_COIN>(2_000_000_000, s.ctx());

        let request_id = vault_proxy::deposit_new_receipt<USDC_TEST_COIN>(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            first_expected_shares,
            &clock,
            s.ctx(),
        );
        assert!(request_id == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    let second_expected_shares: u256 = 1_500_000_000u256;

    // Attempt to top up the same receipt while it is still pending; expect Volo abort.
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let coin = coin::mint_for_testing<USDC_TEST_COIN>(1_500_000_000, s.ctx());

        let _ = vault_proxy::deposit_with_receipt<USDC_TEST_COIN>(
            &mut vault,
            &mut reward_manager,
            coin,
            1_500_000_000,
            second_expected_shares,
            receipt,
            &clock,
            s.ctx(),
        );
        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// Delegating to withdraw should pass through Volo's lock checks so the request aborts as expected.
#[expected_failure(abort_code = 4_003, location = user_entry)]
public fun withdraw_respects_volo_locking_rules() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

    let expected_shares: u256 = 2_000_000_000u256;

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();
        let coin = coin::mint_for_testing<USDC_TEST_COIN>(2_000_000_000, s.ctx());

        let _ = vault_proxy::deposit_new_receipt<USDC_TEST_COIN>(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let shares: u256 = 1_000_000_000u256;

        let _ = vault_proxy::request_withdraw_auto_transfer<USDC_TEST_COIN>(
            &mut vault,
            shares,
            1_000_000_000,
            &mut receipt,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// After the operator executes the queued deposit, the receipt should reflect newly minted shares.
public fun deposit_execution_mints_receipt_shares() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

    // Configure oracle decimals/prices so deposits can mint shares deterministically.
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        clock::set_for_testing(&mut clock, 1_000);
        let prices = vector[ORACLE_DECIMALS, 2 * ORACLE_DECIMALS, ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);
        test_scenario::return_shared(oracle_config);
    };

    // Submit a user deposit through the wrapper, expecting a 2x share mint once executed.
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();
        let coin = coin::mint_for_testing<USDC_TEST_COIN>(1_000_000_000, s.ctx());
        let expected_shares: u256 = 2_000_000_000u256;

        let request_id = vault_proxy::deposit_new_receipt<USDC_TEST_COIN>(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            &clock,
            s.ctx(),
        );
        assert!(request_id == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute the queued deposit via the operator flow so shares are minted onto the receipt.
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();
        let max_shares_received: u256 =
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffu256;

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            max_shares_received,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    // The receipt should now hold minted shares with no pending balances.
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() >= 2_000_000_000u256);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}