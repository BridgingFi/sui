# Frontend Architecture Design

**Last Updated**: 2025-11-25

## Overview

This document describes key frontend architecture design decisions, including data fetching, contract interactions, and error handling. For implementation details, refer to the codebase.

---

## Data Fetching

### Sui RPC Queries

**Library**: `@mysten/dapp-kit` with `@tanstack/react-query`

**Pattern**: Use `useSuiClientQuery` hook for RPC queries

**Key Queries**:

- `getObject` - Query object state
- `getOwnedObjects` - Query user's owned objects
- `getDynamicFields` - Query table entries
- `multiGetObjects` - Batch object queries

**Caching**: React Query handles caching (default staleTime: 30-60s)

**Example**:

```typescript
const { data, isLoading } = useSuiClientQuery("getObject", {
  id: objectId,
  options: { showContent: true },
});
```

### GraphQL Queries

**Use Case**: Query Switchboard Aggregators via Sui GraphQL API

**Implementation**: Direct `fetch` calls to GraphQL endpoint

**Location**: `web/src/hooks/useSwitchboardAggregators.ts`

**Pattern**:

- POST request to GraphQL endpoint
- Query `objects` with type filter
- Support cursor-based pagination
- Parse JSON response from `asMoveObject.contents.json`

**GraphQL Endpoint**: `VITE_SUI_GRAPHQL_URL` environment variable

---

## Contract Interactions

### Transaction Building

**Library**: `@mysten/sui/transactions`

**Pattern**: Build transactions using `Transaction` class

**Key Methods**:

- `tx.moveCall()` - Call Move function
- `tx.object()` - Reference object
- `tx.pure.*()` - Pass pure values
- `tx.build({ client })` - Build transaction bytes

**Example**:

```typescript
const tx = new Transaction();
tx.moveCall({
  target: `${PACKAGE_ID}::module::function`,
  arguments: [tx.object(objectId), tx.pure.u64(amount)],
});
```

### Transaction Execution

**Library**: `@mysten/dapp-kit`

**Hook**: `useSignAndExecuteTransaction()`

**Pattern**: Use `mutate` function with transaction

**Error Handling**: Unified via `showTransactionErrorToast()`

**Example**:

```typescript
const { mutate: signAndExecute } = useSignAndExecuteTransaction({
  onSuccess: () => {
    // Handle success
  },
  onError: (err) => {
    showTransactionErrorToast(err, tx, client, errorLog, "Transaction failed");
  },
});

signAndExecute({ transaction: tx });
```

### Transaction Error Handling

**Unified System**: `showTransactionErrorToast()` in `web/src/utils/transaction.tsx`

**Features**:

- Automatically analyzes failed transactions by building them
- Extracts Move error codes from `dryRunTransactionBlock` responses
- Maps error codes to user-friendly messages via `ALL_ERROR_CODES`
- Skips analysis for user rejection errors

**Error Extraction Priority**:

1. `abortError.error_code` from `dryRunTransactionBlock` response
2. `status.error` from transaction effects
3. `err.message` as fallback

**Error Code Mapping**: `web/src/utils/errorCodes.ts` maps error codes (1xxx-5xxx ranges) to readable messages.

---

## State Management

### React Query

**Purpose**: Server state management for on-chain data

**Features**:

- Automatic caching and refetching
- Loading and error states
- Optimistic updates support

**Configuration**:

- `staleTime`: 30-60 seconds for most queries
- `refetchInterval`: 30 seconds for real-time data (vault info)
- Automatic refetch on window focus and account change

### Local State

**Pattern**: `useState` for UI state, `useMemo` for derived data

**Examples**:

- Form inputs
- Modal open/close state
- Filter/search state

---

## Component Organization

### Hooks

**Location**: `web/src/hooks/`

**Categories**:

- **Permission**: `useAdminCap`, `useOperatorCaps`, `useManagePermission`
- **Data**: `useVaultRegistry`, `useVaultRequests`, `useOracleConfig`, `useSwitchboardAggregators`
- **User**: `useUserReceipts`, `useReceiptDetails`

**Pattern**: Each hook encapsulates data fetching logic and returns standardized interface.

### Components

**Location**: `web/src/components/`

**Structure**:

- `layout/` - Layout components (Navbar, etc.)
- `manage/` - Management interface components
- `vault/` - User-facing vault components

**Pattern**: Components use hooks for data, handle UI state locally.

---

## Route Protection

**Protected Routes**:

- `/manage` and `/manage/:vaultId` - AdminCap OR OperatorCap
- `/manage/operator-caps` - AdminCap ONLY
- `/manage/oracle-config` - AdminCap OR OperatorCap (view-only for non-AdminCap)

**Implementation**: Routes use permission hooks and `<Navigate>` for declarative redirects.

**Note**: Management interface is currently part of demo for convenience, should be separate project in production.

---

## Related Documentation

- **Move Contracts**: `move/local_dependencies/volo-smart-contracts/volo-vault/sources/`
- **Frontend Hooks**: `web/src/hooks/`
- **Management Components**: `web/src/components/manage/`
- **Error Handling**: `web/src/utils/transaction.tsx`, `web/src/utils/errorCodes.ts`
- **Permissions**: `docs/permissions.md`

---

## References

- [Sui Move Documentation](https://docs.sui.io/)
- [@mysten/dapp-kit](https://sdk.mystenlabs.com/dapp-kit)
- [@tanstack/react-query](https://tanstack.com/query)
- [HeroUI Documentation](https://www.heroui.com/)
