# BridgingFi Vault Technical Design

## Overview

- Provide a minimum viable Sui vault experience reusing the audited `volo_vault` package without modification.
- Support end-user deposit and withdraw flows for any `CoinType` that the upstream vault supports (USDC on testnet for the demo).
- Keep project-specific logic in a thin wrapper so upgrades can happen independently of the upstream contracts.

## Move Package Layout

- Package: `move/vault`
- Module: `bridgingfi_vault::vault_proxy`
  - `deposit_new_receipt<CoinType>`: creates a fresh Volo receipt by delegating to `volo_vault::user_entry::deposit_with_auto_transfer` with `None` receipt input.
  - `deposit_with_receipt<CoinType>`: tops up an existing receipt by passing it through the same Volo helper.
  - `request_withdraw_auto_transfer<CoinType>`: triggers `volo_vault::user_entry::withdraw_with_auto_transfer` so redeemed coins are delivered directly once the operator executes the queue.
- Rely on `std::option` to toggle between `None` and `Some(receipt)` because Move 2024 forbids `Option` parameters in `entry` functions.
- All functions accept generic `CoinType` to avoid hard-coding specific coin types.

## External Dependencies

- The demo targets Sui testnet USDC at `0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC`.

### volo_vault Package Dependency

`volo_vault` must be published as a local dependency to obtain independent `AdminCap` ownership. The `volo_vault::vault::init()` function transfers `AdminCap` to the package publisher, and `create_vault()` requires `AdminCap` to create Vault instances.

- Managed via Git Subtree (see `move/local_dependencies/README.md` for setup and update instructions).
- Development uses local path dependency; deployment uses network-specific branches with published addresses.
- **Only depends on Switchboard** (via local dependency), simplifying deployment. Volo Vault has been streamlined to remove DeFi protocol adapters (Navi, Suilend, Cetus, etc.) while maintaining core functionality.

See `move/local_dependencies/README.md` for deployment instructions.

## Transaction Flows

- **Deposit (new receipt)**: user supplies a `Coin<CoinType>` and expected share amount; wrapper forwards to Volo helper with `None` receipt to mint shares and emit Volo events.
- **Deposit (existing receipt)**: user passes an owned receipt object; wrapper sends `Some(receipt)` so Volo increments the same position.
- **Withdraw**: user passes a mutable receipt reference plus share amount; wrapper calls the Volo withdraw helper, preserving queue semantics and letting the vault operator fulfil the request.
- The wrapper does not manage pause flags, admin queues, or profit ledgers; these features are deferred to future iterations.

## Frontend Skeleton

- Tech stack: React + HeroUI, `@mysten/dapp-kit` for wallet connections, and `vite` for lightweight bundling.
- Routes: `/` (user portal) and `/admin` (future operator tools placeholder).
- Core components to build next:
  - Wallet connect button plus account state context.
  - Deposit form that constructs `deposit_new_receipt` or `deposit_with_receipt` transactions depending on whether the user holds a receipt.
  - Withdraw form that wraps `request_withdraw_auto_transfer`.
- Avoid external caching layers; read on-chain state directly through Sui RPC.

## Testing Strategy

- Run `sui move test -p move/vault` once dependencies are fetched; tests will live next to the Move sources when authored.
- For faster test execution, use `sui move test --skip-fetch-latest-git-deps` to skip git dependency updates (approximately 4x faster when dependencies haven't changed).
- Future additions: integration harness exercising deposit/withdraw using `sui-test-validator`.

## Deployment Notes

- Publish the Move package to Sui testnet and record the resulting module IDs.
- Store published addresses in frontend environment variables (e.g., `VITE_VAULT_PACKAGE_ID`).
- Ensure CLI and frontend use the same `CoinType` type argument; for the demo this means passing the published USDC type tag.
