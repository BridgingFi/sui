# Transaction Debugging Guide

**Last Updated**: 2025-11-28

## Background

When a transaction fails during `signAndExecute` in the wallet, the transaction is not submitted to the chain. This means we cannot use `sui replay` to get trace files for debugging, as replay requires a transaction digest from an on-chain transaction.

**Solution**: Send the failing transaction to the chain using PTB commands (even if it will fail, it will still be recorded on-chain with a digest), then use `sui replay` and Move debugger to debug the transaction.

## Complete Debugging Workflow

### Step 1: Generate PTB Command from Failed Transaction

When a transaction fails in the frontend, extract the transaction parameters and generate a `sui client ptb` command. The PTB command should match the exact transaction that failed, including all move calls, arguments, and type parameters.

**Key Points**:

- Extract all parameters from the Transaction object (object IDs, type arguments, pure values)
- Convert `tx.object()` → `@objectId` in PTB format
- Convert `tx.pure.*` → direct values in PTB format
- Convert type arguments → `<Type>` in PTB format
- Chain multiple move calls with `\` line continuation

### Step 2: Send Transaction to Chain

Execute the PTB command to send the transaction to the chain:

```bash
sui client ptb \
  --move-call "package::module::function" "<Type>" "@objectId" "value" \
  --gas-budget 100000000
```

### Step 3: Get Trace File

Use `sui replay` to get the trace file for debugging:

```bash
sui replay --trace --digest <transaction_digest> --overwrite
```

This will create a trace file at `.replay/<digest>/trace.json.zst`.

### Step 4: Set Up Symbolic Link

Create a symbolic link from the Move package build directory to the replay directory so the Move debugger can find the source code:

```bash
ln -s move/local_dependencies/volo-smart-contracts/volo-vault/build/volo_vault \
  .replay/<digest>/0x<package_id>/source/volo_vault
```

### Step 5: Debug with Move Debugger

Open the trace file with Move debugger:

```bash
move debugger .replay/<digest>/trace.json.zst
```

You can now step through the execution, inspect variables, and identify the cause of the failure.

## Notes

- This debugging method is only needed with a failed transaction that won't be submitted
- The transaction will fail on-chain, but this is expected - we need to replay with tracing
