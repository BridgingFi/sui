# Architecture Plan

Long-term product vision and phased delivery strategy for the BridgingFi vault.

## Phase Roadmap

### Phase 0 – MVP (In Progress)

**Move Contracts**:

- ✅ `vault_registry` - Vault registration and management
- ✅ `vault_proxy` - User deposit/withdraw wrappers
- ✅ Custom adapters - For off-chain investments (UK lending market)

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
