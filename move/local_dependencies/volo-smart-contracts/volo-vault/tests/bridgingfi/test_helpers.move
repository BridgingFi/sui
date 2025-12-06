#[test_only]
module volo_vault::bridgingfi_test_helpers;

use sui::clock::Clock;
use sui::test_scenario::{Self, Scenario};
use volo_vault::bridgingfi_adapter::{Self, BridgingFiPosition};
use volo_vault::operation;
use volo_vault::test_helpers;
use volo_vault::vault::{Self, Operation, OperatorCap, Vault};
use volo_vault::vault_oracle::OracleConfig;
use volo_vault::vault_utils;

#[test_only]
public fun init_create_bridgingfi_position<PrincipalCoinType>(
  s: &mut Scenario,
  custodian_account: address,
  apr_decimal: u256,
) {
  let owner = s.sender();

  s.next_tx(owner);
  {
    let mut vault = s.take_shared<Vault<PrincipalCoinType>>();
    let operation = s.take_shared<Operation>();
    let cap = s.take_from_sender<OperatorCap>();

    let position = bridgingfi_adapter::create_position(
      vault.vault_id(),
      custodian_account,
      apr_decimal,
      s.ctx(),
    );

    operation::add_new_defi_asset(
      &operation,
      &cap,
      &mut vault,
      0,
      position,
    );

    test_scenario::return_shared(vault);
    test_scenario::return_shared(operation);
    s.return_to_sender(cap);
  };
}

// Default prices: SUI=2, USDC=1, BTC=100000 (in ORACLE_DECIMALS format)
const DEFAULT_SUI_PRICE: u256 = 2 * 1_000_000_000_000_000_000;
const DEFAULT_USDC_PRICE: u256 = 1 * 1_000_000_000_000_000_000;
const DEFAULT_BTC_PRICE: u256 = 100_000 * 1_000_000_000_000_000_000;

#[test_only]
/// Setup oracle with default prices (SUI=2, USDC=1, BTC=100000)
public fun setup_oracle_with_default_prices(
  s: &mut Scenario,
  clock: &mut Clock,
) {
  let owner = s.sender();

  s.next_tx(owner);
  {
    let mut oracle_config = s.take_shared<OracleConfig>();
    test_helpers::set_aggregators(s, clock, &mut oracle_config);
    let prices = vector[DEFAULT_SUI_PRICE, DEFAULT_USDC_PRICE, DEFAULT_BTC_PRICE];
    test_helpers::set_prices(s, clock, &mut oracle_config, prices);
    test_scenario::return_shared(oracle_config);
  };
}

#[test_only]
/// Setup initial position state (outstanding_balance and last_update_day)
public fun setup_initial_position_state<PrincipalCoinType>(
  s: &mut Scenario,
  outstanding_balance: u64,
  last_update_day: u64,
) {
  let owner = s.sender();

  s.next_tx(owner);
  {
    let mut vault = s.take_shared<Vault<PrincipalCoinType>>();
    let bridgingfi_asset_type = vault_utils::parse_key<BridgingFiPosition>(0);
    let mut position = vault::borrow_defi_asset<
      PrincipalCoinType,
      BridgingFiPosition,
    >(
      &mut vault,
      bridgingfi_asset_type,
    );

    bridgingfi_adapter::set_outstanding_balance(
      &mut position,
      outstanding_balance,
    );
    bridgingfi_adapter::update_last_update_day(&mut position, last_update_day);

    vault::return_defi_asset(&mut vault, bridgingfi_asset_type, position);
    test_scenario::return_shared(vault);
  };
}
