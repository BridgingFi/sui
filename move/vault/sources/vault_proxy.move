// TODO: This file is marked for deletion. These proxy functions are no longer needed.
module bridgingfi_vault::vault_proxy;

use sui::clock::Clock;
use volo_vault::receipt::Receipt;
use volo_vault::reward_manager::RewardManager;
use volo_vault::user_entry;
use volo_vault::vault::Vault;

/// Deposit into Volo vault creating a new receipt.
#[deprecated(note = b"This function is deprecated and will be removed. Use direct volo_vault functions instead.")]
#[allow(lint(public_entry))]
public entry fun deposit_new_receipt<CoinType>(
  vault: &mut Vault<CoinType>,
  reward_manager: &mut RewardManager<CoinType>,
  coin: sui::coin::Coin<CoinType>,
  amount: u64,
  expected_shares: u256,
  clock: &Clock,
  ctx: &mut sui::tx_context::TxContext,
): u64 {
  abort 1
}

/// Deposit into Volo vault using an existing receipt.
#[deprecated(note = b"This function is deprecated and will be removed. Use direct volo_vault functions instead.")]
#[allow(lint(public_entry))]
public entry fun deposit_with_receipt<CoinType>(
  vault: &mut Vault<CoinType>,
  reward_manager: &mut RewardManager<CoinType>,
  coin: sui::coin::Coin<CoinType>,
  amount: u64,
  expected_shares: u256,
  receipt: Receipt,
  clock: &Clock,
  ctx: &mut sui::tx_context::TxContext,
): u64 {
  abort 1
}

/// Request a withdraw and auto-transfer proceeds when executed.
#[deprecated(note = b"This function is deprecated and will be removed. Use direct volo_vault functions instead.")]
#[allow(lint(public_entry))]
public entry fun request_withdraw_auto_transfer<CoinType>(
  vault: &mut Vault<CoinType>,
  shares: u256,
  expected_amount: u64,
  receipt: &mut Receipt,
  clock: &Clock,
  ctx: &mut sui::tx_context::TxContext,
): u64 {
  abort 1
}
