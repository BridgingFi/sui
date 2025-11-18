module bridgingfi_vault::vault_registry;

use sui::clock::{Self, Clock};
use sui::event;
use sui::object;
use sui::tx_context::TxContext;
use sui::vec_map::{Self, VecMap};
use volo_vault::reward_manager::RewardManager;
use volo_vault::vault::Vault;

// ==================== Constants ====================

const E_UNAUTHORIZED: u64 = 1;
const E_VAULT_ALREADY_REGISTERED: u64 = 2;

// ==================== Structs ====================

/// Vault registration information
public struct VaultInfo has copy, drop, store {
  vault_id: address,
  reward_manager_id: address,
  coin_type: vector<u8>, // CoinType as string (currently only USDC)
  created_at_ms: u64,
  creator: address,
}

/// Vault registry (Shared Object)
public struct VaultRegistry has key {
  id: object::UID,
  vaults: VecMap<address, VaultInfo>,
  admin: address,
}

/// Registration event
public struct VaultRegisteredEvent has copy, drop {
  vault_id: address,
  reward_manager_id: address,
  coin_type: vector<u8>,
  creator: address,
  timestamp_ms: u64,
}

// ==================== Public Entry Functions ====================

/// Create the vault registry (one-time setup)
/// Transfers the registry as a shared object
public fun create_registry(admin: address, ctx: &mut TxContext) {
  let registry = VaultRegistry {
    id: object::new(ctx),
    vaults: vec_map::empty(),
    admin,
  };
  transfer::share_object(registry);
}

/// Register a vault by ID (admin only)
/// coin_type_str: CoinType as string (e.g., "0x...::usdc::USDC")
#[allow(lint(public_entry))]
public entry fun register_vault_by_id<CoinType>(
  registry: &mut VaultRegistry,
  vault: &Vault<CoinType>,
  reward_manager: &RewardManager<CoinType>,
  coin_type_str: vector<u8>,
  clock: &Clock,
  ctx: &mut TxContext,
) {
  // Permission check: only admin can register
  let sender = tx_context::sender(ctx);
  assert!(sender == registry.admin, E_UNAUTHORIZED);

  // Get vault and reward manager IDs
  let vault_id = vault.vault_id();
  let reward_manager_id = object::id(reward_manager).to_address();

  // Check if vault is already registered
  assert!(
    !vec_map::contains(&registry.vaults, &vault_id),
    E_VAULT_ALREADY_REGISTERED,
  );

  // Get current timestamp
  let timestamp_ms = clock::timestamp_ms(clock);

  // Create vault info
  let vault_info = VaultInfo {
    vault_id,
    reward_manager_id,
    coin_type: coin_type_str,
    created_at_ms: timestamp_ms,
    creator: sender,
  };

  // Register vault
  vec_map::insert(&mut registry.vaults, vault_id, vault_info);

  // Emit event
  event::emit(VaultRegisteredEvent {
    vault_id,
    reward_manager_id,
    coin_type: coin_type_str,
    creator: sender,
    timestamp_ms,
  });
}

// ==================== View Functions ====================

/// Get all registered vaults
public fun get_all_vaults(registry: &VaultRegistry): vector<VaultInfo> {
  let mut result = vector::empty<VaultInfo>();
  let keys = vec_map::keys(&registry.vaults);
  let len = vector::length(&keys);
  let mut i = 0;
  while (i < len) {
    let key = *vector::borrow(&keys, i);
    let info = *vec_map::get(&registry.vaults, &key);
    vector::push_back(&mut result, info);
    i = i + 1;
  };
  result
}

/// Get vault info by vault ID
public fun get_vault_info(
  registry: &VaultRegistry,
  vault_id: address,
): Option<VaultInfo> {
  if (vec_map::contains(&registry.vaults, &vault_id)) {
    option::some(*vec_map::get(&registry.vaults, &vault_id))
  } else {
    option::none()
  }
}

/// Get the number of registered vaults
public fun vault_count(registry: &VaultRegistry): u64 {
  vec_map::length(&registry.vaults)
}

/// Get the admin address
public fun get_admin(registry: &VaultRegistry): address {
  registry.admin
}

/// Get vault ID from VaultInfo
public fun vault_id(info: &VaultInfo): address {
  info.vault_id
}

/// Get reward manager ID from VaultInfo
public fun reward_manager_id(info: &VaultInfo): address {
  info.reward_manager_id
}

/// Get coin type from VaultInfo
public fun coin_type(info: &VaultInfo): vector<u8> {
  info.coin_type
}

/// Get created timestamp from VaultInfo
public fun created_at_ms(info: &VaultInfo): u64 {
  info.created_at_ms
}

/// Get creator address from VaultInfo
public fun creator(info: &VaultInfo): address {
  info.creator
}
