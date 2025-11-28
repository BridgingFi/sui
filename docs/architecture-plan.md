# Architecture Plan

Long-term product vision and phased delivery strategy for the BridgingFi vault.

## Phase Roadmap

### Phase 0 – MVP (In Progress)

**Move Contracts**:

- ✅ `vault_registry` - Vault registration and management
- ✅ `vault_proxy` - User deposit/withdraw wrappers
- 🚧 Custom adapters - For off-chain investments (UK lending market)

**Frontend**:

- ✅ Management interface (`/manage`) - Vault, OperatorCap, OracleConfig management
- 🚧 User portal (`/`) - Deposit, withdraw, receipt management

**Infrastructure**:

- ✅ CLI scripts - Registry and operator operations
- ✅ Error handling and testing infrastructure

### Phase 1 – Operational Controls

- Admin rotation and pause management
- 24-hour withdrawal queue for off-chain investments
- Admin UI for operational controls

### Phase 2 – Profit & Treasury Management

- Profit tracking and ledger
- Profit history in UI

### Phase 3 – Monitoring & Automation

- Monitoring and alerting
- Automated reporting

## Custom Adapter Strategy (Phase 0)

**Status**: Required for MVP to support off-chain investments (UK lending market).

**Design**: Implement custom adapters using Volo Vault's adapter pattern to update asset values without requiring asset return.

**How It Works**:

1. Custom adapter implements value calculation logic (e.g., APR-based for UK lending)
2. Adapter calls `vault.finish_update_asset_value()` to update USD value
3. Share price reflects updated asset values
4. No asset return required - only value updates

**Example: Off-Chain Investment Adapter**

- **Use Case**: UK lending market investments
- **Value Calculation**: `Value = Principal + (Principal × APR × days / 365)`
- **Implementation**: `bridgingfi_vault::adaptors::off_chain_adaptor` module
