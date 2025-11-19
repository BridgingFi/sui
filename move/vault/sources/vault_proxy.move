module bridgingfi_vault::vault_proxy;

use sui::clock::Clock;
use volo_vault::receipt::Receipt;
use volo_vault::reward_manager::RewardManager;
use volo_vault::user_entry;
use volo_vault::vault::Vault;

/// Deposit into Volo vault creating a new receipt.
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
  let original = std::option::none<Receipt>();
  user_entry::deposit_with_auto_transfer<CoinType>(
    vault,
    reward_manager,
    coin,
    amount,
    expected_shares,
    original,
    clock,
    ctx,
  )
}

/// Deposit into Volo vault using an existing receipt.
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
  let original = std::option::some(receipt);
  user_entry::deposit_with_auto_transfer<CoinType>(
    vault,
    reward_manager,
    coin,
    amount,
    expected_shares,
    original,
    clock,
    ctx,
  )
}

/// Request a withdraw and auto-transfer proceeds when executed.
#[allow(lint(public_entry))]
public entry fun request_withdraw_auto_transfer<CoinType>(
  vault: &mut Vault<CoinType>,
  shares: u256,
  expected_amount: u64,
  receipt: &mut Receipt,
  clock: &Clock,
  ctx: &mut sui::tx_context::TxContext,
): u64 {
  user_entry::withdraw_with_auto_transfer<CoinType>(
    vault,
    shares,
    expected_amount,
    receipt,
    clock,
    ctx,
  )
}
