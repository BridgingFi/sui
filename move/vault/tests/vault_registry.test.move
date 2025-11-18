#[test_only]
module bridgingfi_vault::vault_registry_test;

use bridgingfi_vault::vault_registry;
use sui::clock;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::reward_manager::RewardManager;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::vault::Vault;

const ADMIN: address = @0xa;
const NON_ADMIN: address = @0xb;

#[test]
public fun test_create_registry() {
  let mut s = test_scenario::begin(ADMIN);
  let mut clock = clock::create_for_testing(s.ctx());

  // Create registry
  s.next_tx(ADMIN);
  {
    vault_registry::create_registry(ADMIN, s.ctx());
  };

  // Verify registry was created as shared object
  s.next_tx(ADMIN);
  {
    let registry = s.take_shared<vault_registry::VaultRegistry>();
    let admin = vault_registry::get_admin(&registry);
    assert!(admin == ADMIN, 0);
    let count = vault_registry::vault_count(&registry);
    assert!(count == 0, 1);
    test_scenario::return_shared(registry);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
public fun test_register_vault() {
  let mut s = test_scenario::begin(ADMIN);
  let mut clock = clock::create_for_testing(s.ctx());

  // Initialize Volo Vault
  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

  // Create registry
  s.next_tx(ADMIN);
  {
    vault_registry::create_registry(ADMIN, s.ctx());
  };

  // Register vault
  s.next_tx(ADMIN);
  {
    let mut registry = s.take_shared<vault_registry::VaultRegistry>();
    let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
    let reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();

    let coin_type_str =
      b"0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC";
    vault_registry::register_vault_by_id<USDC_TEST_COIN>(
      &mut registry,
      &vault,
      &reward_manager,
      coin_type_str,
      &clock,
      s.ctx(),
    );

    test_scenario::return_shared(registry);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(reward_manager);
  };

  // Verify vault was registered
  s.next_tx(ADMIN);
  {
    let registry = s.take_shared<vault_registry::VaultRegistry>();
    let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
    let vault_id = vault.vault_id();

    let count = vault_registry::vault_count(&registry);
    assert!(count == 1, 0);

    let vault_info_opt = vault_registry::get_vault_info(&registry, vault_id);
    assert!(option::is_some(&vault_info_opt), 1);
    let vault_info = option::borrow(&vault_info_opt);
    assert!(vault_registry::vault_id(vault_info) == vault_id, 2);

    let all_vaults = vault_registry::get_all_vaults(&registry);
    assert!(vector::length(&all_vaults) == 1, 3);

    test_scenario::return_shared(registry);
    test_scenario::return_shared(vault);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
#[
  expected_failure(
    abort_code = bridgingfi_vault::vault_registry::E_UNAUTHORIZED,
  ),
]
public fun test_register_vault_unauthorized() {
  let mut s = test_scenario::begin(ADMIN);
  let mut clock = clock::create_for_testing(s.ctx());

  // Initialize Volo Vault
  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

  // Create registry
  s.next_tx(ADMIN);
  {
    vault_registry::create_registry(ADMIN, s.ctx());
  };

  // Try to register vault as non-admin (should fail)
  s.next_tx(NON_ADMIN);
  {
    let mut registry = s.take_shared<vault_registry::VaultRegistry>();
    let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
    let reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();

    let coin_type_str =
      b"0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC";
    vault_registry::register_vault_by_id<USDC_TEST_COIN>(
      &mut registry,
      &vault,
      &reward_manager,
      coin_type_str,
      &clock,
      s.ctx(),
    );

    test_scenario::return_shared(registry);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(reward_manager);
  };

  clock.destroy_for_testing();
  s.end();
}

#[test]
#[
  expected_failure(
    abort_code = bridgingfi_vault::vault_registry::E_VAULT_ALREADY_REGISTERED,
  ),
]
public fun test_register_vault_twice() {
  let mut s = test_scenario::begin(ADMIN);
  let mut clock = clock::create_for_testing(s.ctx());

  // Initialize Volo Vault
  init_vault::init_vault(&mut s, &mut clock);
  init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
  init_vault::init_create_reward_manager<USDC_TEST_COIN>(&mut s);

  // Create registry
  s.next_tx(ADMIN);
  {
    vault_registry::create_registry(ADMIN, s.ctx());
  };

  // Register vault first time
  s.next_tx(ADMIN);
  {
    let mut registry = s.take_shared<vault_registry::VaultRegistry>();
    let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
    let reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();

    let coin_type_str =
      b"0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC";
    vault_registry::register_vault_by_id<USDC_TEST_COIN>(
      &mut registry,
      &vault,
      &reward_manager,
      coin_type_str,
      &clock,
      s.ctx(),
    );

    test_scenario::return_shared(registry);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(reward_manager);
  };

  // Try to register same vault again (should fail)
  s.next_tx(ADMIN);
  {
    let mut registry = s.take_shared<vault_registry::VaultRegistry>();
    let vault = s.take_shared<Vault<USDC_TEST_COIN>>();
    let reward_manager = s.take_shared<RewardManager<USDC_TEST_COIN>>();

    let coin_type_str =
      b"0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC";
    vault_registry::register_vault_by_id<USDC_TEST_COIN>(
      &mut registry,
      &vault,
      &reward_manager,
      coin_type_str,
      &clock,
      s.ctx(),
    );

    test_scenario::return_shared(registry);
    test_scenario::return_shared(vault);
    test_scenario::return_shared(reward_manager);
  };

  clock.destroy_for_testing();
  s.end();
}
