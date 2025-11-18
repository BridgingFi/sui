# Local Dependencies

Local dependencies managed via Git Subtree. Based on [Atlassian Git Subtree tutorial](https://www.atlassian.com/git/tutorials/git-subtree).

## Notes

- **Subdirectories**: `git subtree` doesn't support pulling subdirectories directly, so we pull the entire repository and reference the needed subdirectory in `Move.toml`.
- **Dummy prefix**: The `--prefix` uses a dummy subdirectory (`dummy`) because git subtree ignores the last directory name and uses the parent directory instead.

## volo-smart-contracts

Used as a dependency in `move/vault`. The `volo-vault` subdirectory is referenced in `move/vault/Move.toml`.

**Note**: `volo-vault` now only depends on Switchboard (via local dependency), simplifying deployment.

### Initial Setup

```bash
git remote add -f volo-smart-contracts https://github.com/Sui-Volo/volo-smart-contracts.git
git subtree add --prefix=move/local_dependencies/volo-smart-contracts/dummy volo-smart-contracts main
```

### Update from Upstream

```bash
git fetch volo-smart-contracts main
git subtree pull --prefix=move/local_dependencies/volo-smart-contracts volo-smart-contracts main
```

## switchboard-xyz-sui

Used as a dependency in `volo-vault` (under `move/local_dependencies/volo-smart-contracts/volo-vault/`). Managed via Git Subtree to enable modification of test function visibility.

### Initial Setup

```bash
git remote add -f switchboard-xyz-sui https://github.com/switchboard-xyz/sui.git
git subtree add --prefix=move/local_dependencies/switchboard-xyz-sui/dummy switchboard-xyz-sui testnet
```

### Update from Upstream

```bash
git fetch switchboard-xyz-sui testnet
git subtree pull --prefix=move/local_dependencies/switchboard-xyz-sui switchboard-xyz-sui testnet
```

## Testnet Deployment

### Dependency Graph

```
volo_vault
└── Switchboard (local) ✅
```

### Deployment Steps

```bash
cd volo-smart-contracts/volo-vault
sui move build
sui client publish --gas-budget 2000000000 --skip-fetch-latest-git-deps
```

### Notes

- Switchboard is managed as a local dependency (via git subtree), allowing modification of test function visibility
- After deployment, update `published-at` and `addresses` in `Move.testnet.toml`
