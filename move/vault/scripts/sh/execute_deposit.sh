#!/bin/bash

# Script to execute a deposit request
# Usage: ./execute_deposit.sh <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> <MAX_SHARES_RECEIVED>
#   - VAULT_ID: The vault object ID
#   - REQUEST_ID: The deposit request ID (u64 number, can be in decimal or hex format like 0x...)
#   - OPERATOR_CAP_ID: The OperatorCap object ID
#   - MAX_SHARES_RECEIVED: Maximum shares to receive (u256)

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

VAULT_ID=${1:-""}
REQUEST_ID=${2:-""}
OPERATOR_CAP_ID=${3:-""}
MAX_SHARES_RECEIVED=${4:-""}

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Validate required parameters
if [ -z "$VAULT_ID" ]; then
  echo "Error: VAULT_ID is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> <MAX_SHARES_RECEIVED>"
  exit 1
fi

if [ -z "$REQUEST_ID" ]; then
  echo "Error: REQUEST_ID is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> <MAX_SHARES_RECEIVED>"
  echo "  REQUEST_ID: The deposit request ID (u64 number, can be in decimal or hex format)"
  exit 1
fi

if [ -z "$OPERATOR_CAP_ID" ]; then
  echo "Error: OPERATOR_CAP_ID is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> <MAX_SHARES_RECEIVED>"
  exit 1
fi

if [ -z "$MAX_SHARES_RECEIVED" ]; then
  echo "Error: MAX_SHARES_RECEIVED is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> <MAX_SHARES_RECEIVED>"
  exit 1
fi

if [ -z "$VOLO_VAULT_PACKAGE_ID" ]; then
  echo "Error: VOLO_VAULT_PACKAGE_ID is not set. Set it as environment variable:"
  echo "  export VOLO_VAULT_PACKAGE_ID=0x..."
  exit 1
fi

if [ -z "$VOLO_OPERATION_ID" ]; then
  echo "Error: VOLO_OPERATION_ID is not set. Set it as environment variable:"
  echo "  export VOLO_OPERATION_ID=0x..."
  exit 1
fi

if [ -z "$VOLO_ORACLE_CONFIG_ID" ]; then
  echo "Error: VOLO_ORACLE_CONFIG_ID is not set. Set it as environment variable:"
  echo "  export VOLO_ORACLE_CONFIG_ID=0x..."
  exit 1
fi

# Constants
SUI_CLOCK_OBJECT_ID="0x6"

echo "Executing Deposit"
echo "Vault ID: $VAULT_ID"
echo "Request ID: $REQUEST_ID"
echo "OperatorCap ID: $OPERATOR_CAP_ID"
echo ""

# Step 1: Query vault object to get coin type and reward_manager_id
echo "Step 1: Querying vault information..."
if ! execute_sui_command "sui client object \"$VAULT_ID\" --json"; then
  echo "Error: Failed to query vault object. Exit code: $_SUI_CMD_EXIT_CODE" >&2
  exit 1
fi
if ! check_sui_json_response "$_SUI_CMD_STDOUT"; then
  exit 1
fi

VAULT_DATA="$_SUI_CMD_STDOUT"

# Extract coin type from vault object type
VAULT_TYPE=$(echo "$VAULT_DATA" | jq -r '.data.type // .type // empty')
COIN_TYPE=""

if [ -n "$VAULT_TYPE" ] && [ "$VAULT_TYPE" != "null" ]; then
  # Extract type argument from generic type: Vault<CoinType>
  COIN_TYPE=$(echo "$VAULT_TYPE" | sed -n 's/.*<\([^>]*\)>.*/\1/p')
fi

if [ -z "$COIN_TYPE" ]; then
  echo "Error: Could not extract coin type from vault type: $VAULT_TYPE"
  exit 1
fi

echo "Coin Type: $COIN_TYPE"

# Extract reward_manager_id from vault fields
REWARD_MANAGER_ID=$(echo "$VAULT_DATA" | jq -r '.content.fields.reward_manager // .data.content.fields.reward_manager // empty')

if [ -z "$REWARD_MANAGER_ID" ] || [ "$REWARD_MANAGER_ID" = "null" ] || [ "$REWARD_MANAGER_ID" = "0x0" ]; then
  echo "Error: Could not extract reward_manager_id from vault. Vault may not have a reward manager set."
  exit 1
fi

echo "Reward Manager ID: $REWARD_MANAGER_ID"
echo "Max Shares Received: $MAX_SHARES_RECEIVED"
echo ""

# Step 2: Execute deposit
echo "Step 2: Executing deposit transaction..."
echo "Calling: ${VOLO_VAULT_PACKAGE_ID}::operation::execute_deposit"
echo ""

if ! execute_sui_command "sui client call --package \"$VOLO_VAULT_PACKAGE_ID\" --module operation --function execute_deposit --type-args \"$COIN_TYPE\" --args \"$VOLO_OPERATION_ID\" \"$OPERATOR_CAP_ID\" \"$VAULT_ID\" \"$REWARD_MANAGER_ID\" \"$SUI_CLOCK_OBJECT_ID\" \"$VOLO_ORACLE_CONFIG_ID\" \"$REQUEST_ID\" \"$MAX_SHARES_RECEIVED\" --gas-budget 100000000 --json"; then
  echo "Error: Transaction failed. Exit code: $_SUI_CMD_EXIT_CODE" >&2
  exit 1
fi
if ! check_sui_json_response "$_SUI_CMD_STDOUT"; then
  exit 1
fi

TX_JSON="$_SUI_CMD_STDOUT"

# Display formatted output
echo "Transaction executed successfully!"
echo ""
echo "Transaction details:"
echo "$TX_JSON" | jq '{
  digest: .digest,
  effects: .effects.status,
  gasUsed: .effects.gasUsed,
  events: [.events[] | select(.type | contains("DepositExecuted"))]
}'

echo ""
echo "=== Summary ==="
echo "Vault ID: $VAULT_ID"
echo "Request ID: $REQUEST_ID"
echo "Transaction Digest: $(echo "$TX_JSON" | jq -r '.digest')"
echo ""
echo "Deposit executed successfully!"

