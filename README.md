# BridgingFi Sui Vault

A minimum viable Sui vault experience built on top of the audited [Volo Vault](https://github.com/volo-protocol/volo-vault) package.

## Overview

This project provides a Sui vault implementation that:

- Reuses the audited `volo_vault` package without modification
- Supports end-user deposit and withdraw flows for any `CoinType` that the upstream vault supports
- Keeps project-specific logic in a thin wrapper for independent upgrades

**Current Demo**: Sui testnet USDC vault

## Project Structure

```
.
├── move/                    # Move smart contracts
│   ├── vault/              # Main vault package
│   │   ├── sources/        # Move modules
│   │   ├── tests/          # Move unit tests
│   │   └── scripts/        # CLI scripts for deployment and operations
│   └── local_dependencies/ # Git subtree dependencies
│       ├── volo-smart-contracts/  # Volo Vault (audited)
│       └── switchboard-xyz-sui/   # Switchboard oracle
├── web/                     # Frontend application
│   └── src/
│       ├── components/     # React components
│       ├── hooks/          # React hooks for data fetching
│       └── routes/        # Route components
└── docs/                    # Documentation
```

## Quick Start

### Prerequisites

- [Sui CLI](https://docs.sui.io/build/install) (latest version)
- [Node.js](https://nodejs.org/) 20+ and [pnpm](https://pnpm.io/)
- Sui testnet account with testnet SUI

### Move Contracts

```bash
# Navigate to Move package
cd move/vault

# Run tests
sui move test -p .

# Run tests with coverage
sui move test -p . --coverage
sui move coverage summary -p .
```

See `move/local_dependencies/README.md` for dependency deployment and `move/vault/scripts/README.md` for operation scripts.

### Frontend

```bash
# Navigate to web directory
cd web

# Install dependencies
pnpm install

# Start development server
pnpm dev
```

## Documentation

- **Technical Design**: [`docs/technical-design.md`](docs/technical-design.md) - Move contract design
- **Frontend Architecture**: [`docs/frontend-architecture.md`](docs/frontend-architecture.md) - Frontend design patterns
- **Permissions**: [`docs/permissions.md`](docs/permissions.md) - Permission system requirements

## Details of Contracts and Frontend

### Move Contracts

- **Vault Registry** (`vault_registry`): Registry for tracking all vault instances
- **Vault Proxy** (`vault_proxy`): Optional wrapper layer (currently unused and may be removed)
- **volo_vault**: Audited vault package (Git subtree, local dependency, should be deployed, defi dependencies removed to simplify deployment)
- **Switchboard**: Price oracle (local dependency, no need to deploy, uses official published package, modifications for testcases only)

### Frontend

- User deposit and withdraw flows
- Management interface for operators (execute requests, manage OracleConfig)
- Real-time vault information display
- Transaction error handling with Move error code mapping

Frontend environment variables (see `web/.env.MODE` for different modes, e.g. `web/.env.development`, `web/.env.testnet`, `web/.env.production`):

## License

See [LICENSE](LICENSE) file.
