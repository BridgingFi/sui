#!/bin/bash

# Script to execute a withdraw request
# Usage: ./execute_withdraw.sh <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> [MAX_AMOUNT_RECEIVED]
#   - VAULT_ID: The vault object ID
#   - REQUEST_ID: The withdraw request ID (u64)
#   - OPERATOR_CAP_ID: The OperatorCap object ID
#   - MAX_AMOUNT_RECEIVED: Optional. Maximum amount to receive (u64). Defaults to expected_amount * 1.1 (10% slippage tolerance)

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

VAULT_ID=${1:-""}
REQUEST_ID=${2:-""}
OPERATOR_CAP_ID=${3:-""}
MAX_AMOUNT_RECEIVED=${4:-""}

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Validate required parameters
if [ -z "$VAULT_ID" ]; then
  echo "Error: VAULT_ID is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> [MAX_AMOUNT_RECEIVED]"
  exit 1
fi

if [ -z "$REQUEST_ID" ]; then
  echo "Error: REQUEST_ID is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> [MAX_AMOUNT_RECEIVED]"
  exit 1
fi

if [ -z "$OPERATOR_CAP_ID" ]; then
  echo "Error: OPERATOR_CAP_ID is required."
  echo "Usage: $0 <VAULT_ID> <REQUEST_ID> <OPERATOR_CAP_ID> [MAX_AMOUNT_RECEIVED]"
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

echo "Executing Withdraw"
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
echo ""

# Step 2: Query withdraw request to get expected_amount if MAX_AMOUNT_RECEIVED not provided
if [ -z "$MAX_AMOUNT_RECEIVED" ]; then
  echo "Step 2: Querying withdraw request to calculate max_amount_received..."
  
  # Get vault request buffer to find withdraw request
  REQUEST_BUFFER=$(echo "$VAULT_DATA" | jq '.content.fields.request_buffer // .data.content.fields.request_buffer // empty')
  
  if [ "$REQUEST_BUFFER" != "null" ] && [ -n "$REQUEST_BUFFER" ]; then
    WITHDRAW_REQUESTS_TABLE=$(echo "$REQUEST_BUFFER" | jq '.fields.withdraw_requests // empty')
    WITHDRAW_REQUESTS_TABLE_ID=$(echo "$WITHDRAW_REQUESTS_TABLE" | jq -r '.fields.id.id // empty')
    
    if [ -n "$WITHDRAW_REQUESTS_TABLE_ID" ] && [ "$WITHDRAW_REQUESTS_TABLE_ID" != "null" ]; then
      # Query dynamic field for this request_id
      if execute_sui_command "sui client dynamic-field \"$WITHDRAW_REQUESTS_TABLE_ID\" --json"; then
        DYNAMIC_FIELD_DATA="$_SUI_CMD_STDOUT"
        
        if ! echo "$DYNAMIC_FIELD_DATA" | jq empty 2>/dev/null; then
          echo "Warning: Invalid JSON from dynamic field query"
        else
          REQUEST_KEY=$(echo "$DYNAMIC_FIELD_DATA" | \
            jq --arg req_id "$REQUEST_ID" '.data[] | select(.name.value == ($req_id | tonumber)) | .objectId' | head -1)
          
          if [ -n "$REQUEST_KEY" ] && [ "$REQUEST_KEY" != "null" ]; then
            if execute_sui_command "sui client object \"$REQUEST_KEY\" --json"; then
              REQUEST_DATA="$_SUI_CMD_STDOUT"
              
              if ! echo "$REQUEST_DATA" | jq empty 2>/dev/null; then
                echo "Warning: Invalid JSON from request object query"
              else
                EXPECTED_AMOUNT=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.expected_amount // .data.content.fields.value.fields.expected_amount // "0"')
                
                if [ "$EXPECTED_AMOUNT" != "0" ] && [ "$EXPECTED_AMOUNT" != "null" ]; then
                  # Calculate max_amount_received as expected_amount * 1.1 (10% slippage tolerance)
                  if command -v bc &> /dev/null; then
                    MAX_AMOUNT_RECEIVED=$(echo "scale=0; ($EXPECTED_AMOUNT * 110) / 100" | bc)
                  else
                    MAX_AMOUNT_RECEIVED=$(awk "BEGIN {printf \"%.0f\", ($EXPECTED_AMOUNT * 110) / 100}")
                  fi
                  echo "Expected Amount: $EXPECTED_AMOUNT"
                  echo "Max Amount Received (calculated): $MAX_AMOUNT_RECEIVED"
                fi
              fi
            else
              echo "Warning: Failed to query request object. Exit code: $_SUI_CMD_EXIT_CODE" >&2
            fi
          fi
        fi
      else
        echo "Warning: Failed to query dynamic field. Exit code: $_SUI_CMD_EXIT_CODE" >&2
      fi
    fi
  fi
  
  # If still not set, use a default large value (max u64)
  if [ -z "$MAX_AMOUNT_RECEIVED" ] || [ "$MAX_AMOUNT_RECEIVED" = "0" ]; then
    echo "Warning: Could not determine expected_amount from request. Using default max_amount_received."
    MAX_AMOUNT_RECEIVED="18446744073709551615"  # Max u64 value
  fi
  echo ""
fi

echo "Max Amount Received: $MAX_AMOUNT_RECEIVED"
echo ""

# Step 3: Execute withdraw
echo "Step 3: Executing withdraw transaction..."
echo "Calling: ${VOLO_VAULT_PACKAGE_ID}::operation::execute_withdraw"
echo ""

if ! execute_sui_command "sui client call --package \"$VOLO_VAULT_PACKAGE_ID\" --module operation --function execute_withdraw --type-args \"$COIN_TYPE\" --args \"$VOLO_OPERATION_ID\" \"$OPERATOR_CAP_ID\" \"$VAULT_ID\" \"$REWARD_MANAGER_ID\" \"$SUI_CLOCK_OBJECT_ID\" \"$VOLO_ORACLE_CONFIG_ID\" \"$REQUEST_ID\" \"$MAX_AMOUNT_RECEIVED\" --gas-budget 100000000 --json"; then
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
  events: [.events[] | select(.type | contains("WithdrawExecuted"))]
}'

echo ""
echo "=== Summary ==="
echo "Vault ID: $VAULT_ID"
echo "Request ID: $REQUEST_ID"
echo "Transaction Digest: $(echo "$TX_JSON" | jq -r '.digest')"
echo ""
echo "Withdraw executed successfully!"

