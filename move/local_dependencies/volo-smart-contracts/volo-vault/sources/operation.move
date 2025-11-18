module volo_vault::operation;

// use cetusclmm::position::Position as CetusPosition;
// use lending_core::account::AccountCap as NaviAccountCap;
// use mmt_v3::position::Position as MomentumPosition;
use std::ascii::String;
use std::type_name::{Self, TypeName};
use sui::address;
use sui::bag::{Self, Bag};
use sui::balance::{Self, Balance};
use sui::clock::Clock;
use sui::coin::Coin;
use sui::event::emit;
// use suilend::lending_market::ObligationOwnerCap as SuilendObligationOwnerCap;
use volo_vault::receipt::Receipt;
use volo_vault::reward_manager::RewardManager;
use volo_vault::vault::{Self, Vault, Operation, OperatorCap};
use volo_vault::vault_oracle::OracleConfig;
use volo_vault::vault_utils;

// ---------------------  Constants  ---------------------//

const VAULT_NORMAL_STATUS: u8 = 0;
const VAULT_DURING_OPERATION_STATUS: u8 = 1;

// --------------------- Errors  ---------------------//

const ERR_VERIFY_SHARE: u64 = 1_001;
const ERR_ASSETS_LENGTH_MISMATCH: u64 = 1_002;
const ERR_ASSETS_NOT_RETURNED: u64 = 1_003;
const ERR_VAULT_ID_MISMATCH: u64 = 1_004;

// ----------------------  Events  ----------------------------//

public struct OperationStarted has copy, drop {
  vault_id: address,
  defi_asset_ids: vector<u8>,
  defi_asset_types: vector<TypeName>,
  principal_coin_type: TypeName,
  principal_amount: u64,
  coin_type_asset_type: TypeName,
  coin_type_asset_amount: u64,
  total_usd_value: u256,
}

public struct OperationEnded has copy, drop {
  vault_id: address,
  defi_asset_ids: vector<u8>,
  defi_asset_types: vector<TypeName>,
  principal_coin_type: TypeName,
  principal_amount: u64,
  coin_type_asset_type: TypeName,
  coin_type_asset_amount: u64,
}

public struct OperationValueUpdateChecked has copy, drop {
  vault_id: address,
  total_usd_value_before: u256,
  total_usd_value_after: u256,
  loss: u256,
}

// ---------------------  Vault status check  ---------------------//

// Vault status check before start op
// The vault must be enabled now -> Disable it
// Reset tolerance (if this is a new epoch)
public(package) fun pre_vault_check<PrincipalCoinType>(
  vault: &mut Vault<PrincipalCoinType>,
  ctx: &TxContext,
) {
  // vault.assert_enabled();
  vault.assert_normal();
  vault.set_status(VAULT_DURING_OPERATION_STATUS);
  vault.try_reset_tolerance(false, ctx);
}

// ---------------------  Operations  ---------------------//

public struct TxBag {
  vault_id: address,
  defi_asset_ids: vector<u8>,
  defi_asset_types: vector<TypeName>,
}

public struct TxBagForCheckValueUpdate {
  vault_id: address,
  defi_asset_ids: vector<u8>,
  defi_asset_types: vector<TypeName>,
  total_usd_value: u256,
  total_shares: u256,
}

public fun start_op_with_bag<T, CoinType, ObligationType>(
  vault: &mut Vault<T>,
  operation: &Operation,
  cap: &OperatorCap,
  clock: &Clock,
  defi_asset_ids: vector<u8>,
  defi_asset_types: vector<TypeName>,
  principal_amount: u64,
  coin_type_asset_amount: u64,
  ctx: &mut TxContext,
): (Bag, TxBag, TxBagForCheckValueUpdate, Balance<T>, Balance<CoinType>) {
  vault::assert_operator_not_freezed(operation, cap);
  pre_vault_check(vault, ctx);

  let mut defi_assets = bag::new(ctx);

  let defi_assets_length = defi_asset_ids.length();
  assert!(defi_assets_length == defi_asset_types.length(), ERR_ASSETS_LENGTH_MISMATCH);

  let mut i = 0;
  while (i < defi_assets_length) {
    let defi_asset_id = defi_asset_ids[i];
    let defi_asset_type = defi_asset_types[i];

    // if (defi_asset_type == type_name::get<NaviAccountCap>()) {
    //     let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(defi_asset_id);
    //     let navi_account_cap = vault.borrow_defi_asset<T, NaviAccountCap>(
    //         vault_utils::parse_key<NaviAccountCap>(defi_asset_id),
    //     );
    //     defi_assets.add<String, NaviAccountCap>(navi_asset_type, navi_account_cap);
    // };

    // if (defi_asset_type == type_name::get<CetusPosition>()) {
    //     let cetus_asset_type = vault_utils::parse_key<CetusPosition>(defi_asset_id);
    //     let cetus_position = vault.borrow_defi_asset<T, CetusPosition>(cetus_asset_type);
    //     defi_assets.add<String, CetusPosition>(cetus_asset_type, cetus_position);
    // };

    // if (defi_asset_type == type_name::get<SuilendObligationOwnerCap<ObligationType>>()) {
    //     let obligation_asset_type = vault_utils::parse_key<
    //         SuilendObligationOwnerCap<ObligationType>,
    //     >(
    //         defi_asset_id,
    //     );
    //     let obligation = vault.borrow_defi_asset<T, SuilendObligationOwnerCap<ObligationType>>(
    //         obligation_asset_type,
    //     );
    //     defi_assets.add<String, SuilendObligationOwnerCap<ObligationType>>(
    //         obligation_asset_type,
    //         obligation,
    //     );
    // };

    // if (defi_asset_type == type_name::get<MomentumPosition>()) {
    //     let momentum_asset_type = vault_utils::parse_key<MomentumPosition>(defi_asset_id);
    //     let momentum_position = vault.borrow_defi_asset<T, MomentumPosition>(
    //         momentum_asset_type,
    //     );
    //     defi_assets.add<String, MomentumPosition>(momentum_asset_type, momentum_position);
    // };

    if (defi_asset_type == type_name::get<Receipt>()) {
      let receipt_asset_type = vault_utils::parse_key<Receipt>(defi_asset_id);
      let receipt = vault.borrow_defi_asset<T, Receipt>(receipt_asset_type);
      defi_assets.add<String, Receipt>(receipt_asset_type, receipt);
    };

    i = i + 1;
  };

  let principal_balance = if (principal_amount > 0) {
    vault.borrow_free_principal(principal_amount)
  } else {
    balance::zero<T>()
  };

  let coin_type_asset_balance = if (coin_type_asset_amount > 0) {
    vault.borrow_coin_type_asset<T, CoinType>(
      coin_type_asset_amount,
    )
  } else {
    balance::zero<CoinType>()
  };

  let total_usd_value = vault.get_total_usd_value(clock);
  let total_shares = vault.total_shares();

  let tx = TxBag {
    vault_id: vault.vault_id(),
    defi_asset_ids,
    defi_asset_types,
  };

  let tx_for_check_value_update = TxBagForCheckValueUpdate {
    vault_id: vault.vault_id(),
    defi_asset_ids,
    defi_asset_types,
    total_usd_value,
    total_shares,
  };

  emit(OperationStarted {
    vault_id: vault.vault_id(),
    defi_asset_ids,
    defi_asset_types,
    principal_coin_type: type_name::get<T>(),
    principal_amount,
    coin_type_asset_type: type_name::get<CoinType>(),
    coin_type_asset_amount,
    total_usd_value,
  });

  (defi_assets, tx, tx_for_check_value_update, principal_balance, coin_type_asset_balance)
}

public fun end_op_with_bag<T, CoinType, ObligationType>(
  vault: &mut Vault<T>,
  operation: &Operation,
  cap: &OperatorCap,
  mut defi_assets: Bag,
  tx: TxBag,
  principal_balance: Balance<T>,
  coin_type_asset_balance: Balance<CoinType>,
) {
  vault::assert_operator_not_freezed(operation, cap);
  vault.assert_during_operation();

  let TxBag {
    vault_id,
    defi_asset_ids,
    defi_asset_types,
  } = tx;

  assert!(vault.vault_id() == vault_id, ERR_VAULT_ID_MISMATCH);

  let length = defi_asset_ids.length();
  let mut i = 0;
  while (i < length) {
    let defi_asset_id = defi_asset_ids[i];
    let defi_asset_type = defi_asset_types[i];

    // if (defi_asset_type == type_name::get<NaviAccountCap>()) {
    //     let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(defi_asset_id);
    //     let navi_account_cap = defi_assets.remove<String, NaviAccountCap>(navi_asset_type);
    //     vault.return_defi_asset(navi_asset_type, navi_account_cap);
    // };

    // if (defi_asset_type == type_name::get<CetusPosition>()) {
    //     let cetus_asset_type = vault_utils::parse_key<CetusPosition>(defi_asset_id);
    //     let cetus_position = defi_assets.remove<String, CetusPosition>(cetus_asset_type);
    //     vault.return_defi_asset(cetus_asset_type, cetus_position);
    // };

    // if (defi_asset_type == type_name::get<SuilendObligationOwnerCap<ObligationType>>()) {
    //     let suilend_asset_type = vault_utils::parse_key<
    //         SuilendObligationOwnerCap<ObligationType>,
    //     >(
    //         defi_asset_id,
    //     );
    //     let obligation = defi_assets.remove<String, SuilendObligationOwnerCap<ObligationType>>(
    //         suilend_asset_type,
    //     );
    //     vault.return_defi_asset(suilend_asset_type, obligation);
    // };

    // if (defi_asset_type == type_name::get<MomentumPosition>()) {
    //     let momentum_asset_type = vault_utils::parse_key<MomentumPosition>(defi_asset_id);
    //     let momentum_position = defi_assets.remove<String, MomentumPosition>(
    //         momentum_asset_type,
    //     );
    //     vault.return_defi_asset(momentum_asset_type, momentum_position);
    // };

    if (defi_asset_type == type_name::get<Receipt>()) {
      let receipt_asset_type = vault_utils::parse_key<Receipt>(defi_asset_id);
      let receipt = defi_assets.remove<String, Receipt>(receipt_asset_type);
      vault.return_defi_asset(receipt_asset_type, receipt);
    };

    i = i + 1;
  };

  emit(OperationEnded {
    vault_id: vault.vault_id(),
    defi_asset_ids,
    defi_asset_types,
    principal_coin_type: type_name::get<T>(),
    principal_amount: principal_balance.value(),
    coin_type_asset_type: type_name::get<CoinType>(),
    coin_type_asset_amount: coin_type_asset_balance.value(),
  });

  vault.return_free_principal(principal_balance);

  if (coin_type_asset_balance.value() > 0) {
    vault.return_coin_type_asset<T, CoinType>(coin_type_asset_balance);
  } else {
    coin_type_asset_balance.destroy_zero();
  };

  vault.enable_op_value_update();

  defi_assets.destroy_empty();
}

public fun end_op_value_update_with_bag<T, ObligationType>(
  vault: &mut Vault<T>,
  operation: &Operation,
  cap: &OperatorCap,
  clock: &Clock,
  tx: TxBagForCheckValueUpdate,
) {
  vault::assert_operator_not_freezed(operation, cap);
  vault.assert_during_operation();

  let TxBagForCheckValueUpdate {
    vault_id,
    defi_asset_ids,
    defi_asset_types,
    total_usd_value,
    total_shares,
  } = tx;

  assert!(vault.vault_id() == vault_id, ERR_VAULT_ID_MISMATCH);

  // First check if all assets has been returned
  let length = defi_asset_ids.length();
  let mut i = 0;
  while (i < length) {
    let defi_asset_id = defi_asset_ids[i];
    let defi_asset_type = defi_asset_types[i];

    // if (defi_asset_type == type_name::get<NaviAccountCap>()) {
    //     let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(defi_asset_id);
    //     assert!(vault.contains_asset_type(navi_asset_type), ERR_ASSETS_NOT_RETURNED);
    // };

    // if (defi_asset_type == type_name::get<CetusPosition>()) {
    //     let cetus_asset_type = vault_utils::parse_key<CetusPosition>(defi_asset_id);
    //     assert!(vault.contains_asset_type(cetus_asset_type), ERR_ASSETS_NOT_RETURNED);
    // };

    // if (defi_asset_type == type_name::get<SuilendObligationOwnerCap<ObligationType>>()) {
    //     let suilend_asset_type = vault_utils::parse_key<
    //         SuilendObligationOwnerCap<ObligationType>,
    //     >(
    //         defi_asset_id,
    //     );
    //     assert!(vault.contains_asset_type(suilend_asset_type), ERR_ASSETS_NOT_RETURNED);
    // };

    // if (defi_asset_type == type_name::get<MomentumPosition>()) {
    //     let momentum_asset_type = vault_utils::parse_key<MomentumPosition>(defi_asset_id);
    //     assert!(vault.contains_asset_type(momentum_asset_type), ERR_ASSETS_NOT_RETURNED);
    // };

    i = i + 1;
  };

  let total_usd_value_before = total_usd_value;
  vault.check_op_value_update_record();
  let total_usd_value_after = vault.get_total_usd_value(
    clock,
  );

  // Update tolerance if there is a loss (there is a max loss limit each epoch)
  let mut loss = 0;
  if (total_usd_value_after < total_usd_value_before) {
    loss = total_usd_value_before - total_usd_value_after;
    vault.update_tolerance(loss);
  };

  assert!(vault.total_shares() == total_shares, ERR_VERIFY_SHARE);

  emit(OperationValueUpdateChecked {
    vault_id: vault.vault_id(),
    total_usd_value_before,
    total_usd_value_after,
    loss,
  });

  vault.set_status(VAULT_NORMAL_STATUS);
  vault.clear_op_value_update_record();
}

// ------------------  Deposit & Withdraw  ------------------//

public fun execute_deposit<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  reward_manager: &mut RewardManager<PrincipalCoinType>,
  clock: &Clock,
  config: &OracleConfig,
  request_id: u64,
  max_shares_received: u256,
) {
  vault::assert_operator_not_freezed(operation, cap);

  reward_manager.update_reward_buffers(vault, clock);

  let deposit_request = vault.deposit_request(request_id);
  reward_manager.update_receipt_reward(vault, deposit_request.receipt_id());

  vault.execute_deposit(
    clock,
    config,
    request_id,
    max_shares_received,
  );
}

public fun batch_execute_deposit<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  reward_manager: &mut RewardManager<PrincipalCoinType>,
  clock: &Clock,
  config: &OracleConfig,
  request_ids: vector<u64>,
  max_shares_received: vector<u256>,
) {
  vault::assert_operator_not_freezed(operation, cap);

  reward_manager.update_reward_buffers(vault, clock);

  request_ids.do!(|request_id| {
    let deposit_request = vault.deposit_request(request_id);
    reward_manager.update_receipt_reward(vault, deposit_request.receipt_id());

    let (_, index) = request_ids.index_of(&request_id);

    vault.execute_deposit(
      clock,
      config,
      request_id,
      max_shares_received[index],
    );
  });
}

public fun cancel_user_deposit<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  request_id: u64,
  receipt_id: address,
  recipient: address,
  clock: &Clock,
) {
  vault::assert_operator_not_freezed(operation, cap);
  let buffered_coin = vault.cancel_deposit(clock, request_id, receipt_id, recipient);
  transfer::public_transfer(buffered_coin, recipient);
}

public fun execute_withdraw<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  reward_manager: &mut RewardManager<PrincipalCoinType>,
  clock: &Clock,
  config: &OracleConfig,
  request_id: u64,
  max_amount_received: u64,
  ctx: &mut TxContext,
) {
  vault::assert_operator_not_freezed(operation, cap);

  reward_manager.update_reward_buffers(vault, clock);

  let withdraw_request = vault.withdraw_request(request_id);
  reward_manager.update_receipt_reward(vault, withdraw_request.receipt_id());

  let (withdraw_balance, recipient) = vault.execute_withdraw(
    clock,
    config,
    request_id,
    max_amount_received,
  );

  if (recipient != address::from_u256(0)) {
    transfer::public_transfer(withdraw_balance.into_coin(ctx), recipient);
  } else {
    vault.add_claimable_principal(withdraw_balance);
  }
}

public fun batch_execute_withdraw<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  reward_manager: &mut RewardManager<PrincipalCoinType>,
  clock: &Clock,
  config: &OracleConfig,
  request_ids: vector<u64>,
  max_amount_received: vector<u64>,
  ctx: &mut TxContext,
) {
  vault::assert_operator_not_freezed(operation, cap);
  reward_manager.update_reward_buffers(vault, clock);

  request_ids.do!(|request_id| {
    let withdraw_request = vault.withdraw_request(request_id);
    reward_manager.update_receipt_reward(vault, withdraw_request.receipt_id());

    let (_, index) = request_ids.index_of(&request_id);

    let (withdraw_balance, recipient) = vault.execute_withdraw(
      clock,
      config,
      request_id,
      max_amount_received[index],
    );

    if (recipient != address::from_u256(0)) {
      transfer::public_transfer(withdraw_balance.into_coin(ctx), recipient);
    } else {
      vault.add_claimable_principal(withdraw_balance);
    }
  });
}

public fun cancel_user_withdraw<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  request_id: u64,
  receipt_id: address,
  recipient: address,
  clock: &Clock,
): u256 {
  vault::assert_operator_not_freezed(operation, cap);
  vault.cancel_withdraw(clock, request_id, receipt_id, recipient)
}

public fun deposit_by_operator<PrincipalCoinType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  clock: &Clock,
  config: &OracleConfig,
  coin: Coin<PrincipalCoinType>,
) {
  vault::assert_operator_not_freezed(operation, cap);
  vault.deposit_by_operator(
    clock,
    config,
    coin,
  );
}

// ---------------------  Set Asset Types  ---------------------//

public fun add_new_coin_type_asset<PrincipalCoinType, AssetType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
) {
  vault::assert_operator_not_freezed(operation, cap);
  vault.add_new_coin_type_asset<PrincipalCoinType, AssetType>();
}

public fun remove_coin_type_asset<PrincipalCoinType, AssetType>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
) {
  vault::assert_operator_not_freezed(operation, cap);
  vault.remove_coin_type_asset<PrincipalCoinType, AssetType>();
}

public fun add_new_defi_asset<PrincipalCoinType, AssetType: key + store>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  idx: u8,
  asset: AssetType,
) {
  vault::assert_operator_not_freezed(operation, cap);
  vault.add_new_defi_asset(idx, asset);
}

public fun remove_defi_asset_support<PrincipalCoinType, AssetType: key + store>(
  operation: &Operation,
  cap: &OperatorCap,
  vault: &mut Vault<PrincipalCoinType>,
  idx: u8,
): AssetType {
  vault::assert_operator_not_freezed(operation, cap);
  vault.remove_defi_asset_support(idx)
}
