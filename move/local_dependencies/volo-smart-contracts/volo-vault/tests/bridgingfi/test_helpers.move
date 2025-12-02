#[test_only]
module volo_vault::bridgingfi_test_helpers;

use sui::test_scenario::{Self, Scenario};
use volo_vault::bridgingfi_adapter;
use volo_vault::operation;
use volo_vault::vault::{Self, Operation, OperatorCap, Vault};

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
