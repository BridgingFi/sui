# Vault Scripts

Shell scripts for creating vaults and registering them to the vault registry.

## Prerequisites

- `jq` must be installed (`apt-get install jq` or `brew install jq`)
- Sui CLI configured with an active address

## Configuration

Scripts automatically detect the network from your Sui CLI configuration. Set required environment variables:

```bash
export VAULT_PACKAGE_ID=0x...
export VOLO_VAULT_PACKAGE_ID=0x...
export ADMIN_CAP_ID=0x...
export REGISTRY_ID=0x...  # Optional
export COIN_TYPE=0x...::usdc::USDC  # Optional, defaults to testnet USDC
```

## Scripts

### `create_registry.sh`

Creates a new vault registry.

```bash
./sh/create_registry.sh
```

### `create_vault.sh`

Creates a vault and reward manager.

```bash
./sh/create_vault.sh [COIN_TYPE]
```

### `register_vault.sh`

Registers an existing vault to the registry.

```bash
./sh/register_vault.sh <VAULT_ID> <REWARD_MANAGER_ID> [COIN_TYPE]
```

### `query_registry.sh`

Queries vault registry to view registered vaults.

```bash
./sh/query_registry.sh [REGISTRY_ID] [VAULT_ID]
```
