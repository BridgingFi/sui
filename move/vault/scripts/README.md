# Vault Scripts

Shell scripts for managing vaults, executing operations, and querying vault state.

## Prerequisites

- `jq` must be installed (`apt-get install jq` or `brew install jq`)
- Sui CLI configured with an active address

## Configuration

Scripts automatically detect the network from your Sui CLI configuration. Modify config.sh or set required environment variables as follows:

```bash
export VAULT_PACKAGE_ID=0x...
export VOLO_VAULT_PACKAGE_ID=0x...
export VOLO_OPERATION_ID=0x...
export VOLO_ORACLE_CONFIG_ID=0x...
export ADMIN_CAP_ID=0x...
export REGISTRY_ID=0x...  # Optional
export COIN_TYPE=0x...::usdc::USDC  # Optional, defaults to testnet USDC
```

**Configuration File**: `config.sh` also provides network detection and unified error handling functions.

**Usage**: All scripts should source `config.sh`:

## Script List

### Registry Management Scripts

| Script               | Function                                 |
| -------------------- | ---------------------------------------- |
| `create_registry.sh` | Create new Vault Registry                |
| `create_vault.sh`    | Create new Volo Vault and Reward Manager |
| `register_vault.sh`  | Register existing Vault to Registry      |
| `query_registry.sh`  | Query Registry for registered Vaults     |

### Operator Operation Scripts

| Script                   | Function                  |
| ------------------------ | ------------------------- |
| `query_operator_caps.sh` | Query OperatorCap objects |
| `execute_deposit.sh`     | Execute deposit requests  |
| `execute_withdraw.sh`    | Execute withdraw requests |
| `cancel_deposit.sh`      | Cancel deposit requests   |
| `cancel_withdraw.sh`     | Cancel withdraw requests  |

### Query Scripts

| Script                    | Function                        |
| ------------------------- | ------------------------------- |
| `query_vault.sh`          | Query vault state               |
| `query_vault_requests.sh` | Query deposit/withdraw requests |
| `query_receipts.sh`       | Query user receipts             |
| `query_receipt_info.sh`   | Query receipt details           |

## References

- [regulated-coin-sample](https://github.com/MystenLabs/regulated-coin-sample) - Sui official example for JSON parsing patterns
- [switchboard-xyz/sui](https://github.com/switchboard-xyz/sui/tree/main/on_demand/scripts) - Switchboard script implementation
