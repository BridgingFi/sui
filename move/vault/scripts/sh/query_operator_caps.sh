#!/bin/bash

# Script to query owned OperatorCap objects for the current account
# Usage: ./query_operator_caps.sh [ADDRESS]
#   - ADDRESS: Optional. If provided, queries for that address. Otherwise queries for current active address.

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

ADDRESS=${1:-""}

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# If no address provided, get active address
if [ -z "$ADDRESS" ]; then
  ADDRESS=$(sui client active-address 2>/dev/null || echo "")
  
  if [ -z "$ADDRESS" ]; then
    echo "Error: No address provided and no active address found."
    echo "Usage: $0 [ADDRESS]"
    echo "  or set an active address: sui client switch --address <ADDRESS>"
    exit 1
  fi
fi

if [ -z "$VOLO_VAULT_PACKAGE_ID" ]; then
  echo "Error: VOLO_VAULT_PACKAGE_ID is not set. Set it as environment variable:"
  echo "  export VOLO_VAULT_PACKAGE_ID=0x..."
  exit 1
fi

echo "Querying OperatorCap objects"
echo "Address: $ADDRESS"
echo "Volo Vault Package ID: $VOLO_VAULT_PACKAGE_ID"
echo ""

# Query owned OperatorCap objects
OPERATOR_CAP_TYPE="${VOLO_VAULT_PACKAGE_ID}::vault::OperatorCap"

echo "=== OperatorCap Objects ==="
# Execute command using utility function
if ! execute_sui_command "sui client objects \"$ADDRESS\" --json"; then
  echo "Error: Failed to query objects. Exit code: $_SUI_CMD_EXIT_CODE" >&2
  exit 1
fi


# Check if the output is valid JSON
if ! check_sui_json_response "$_SUI_CMD_STDOUT"; then
  exit 1
fi

# Check for errors in JSON response (sui client objects returns array, not object with error field)
# But we should check if it's an array
if ! echo "$_SUI_CMD_STDOUT" | jq -e 'type == "array"' > /dev/null 2>&1; then
  echo "Error: Unexpected response format:"
  echo "$_SUI_CMD_STDOUT"
  exit 1
fi

# Filter OperatorCap objects by type
# sui client objects returns array format: [{data: {...}}, ...]
OPERATOR_CAPS_ARRAY=$(echo "$_SUI_CMD_STDOUT" | jq --arg cap_type "$OPERATOR_CAP_TYPE" '[.[]? | select(.data.type? == $cap_type)]')

if [ -z "$OPERATOR_CAPS_ARRAY" ] || [ "$OPERATOR_CAPS_ARRAY" = "[]" ] || [ "$OPERATOR_CAPS_ARRAY" = "null" ]; then
  echo "No OperatorCap objects found for address: $ADDRESS"
  exit 0
fi

CAP_COUNT=$(echo "$OPERATOR_CAPS_ARRAY" | jq 'length')
echo "Found $CAP_COUNT OperatorCap object(s):"
echo ""

# Display each OperatorCap
echo "$OPERATOR_CAPS_ARRAY" | jq -r '.[] | 
  . as $cap |
  ($cap.data.objectId) as $object_id |
  ($cap.data.type) as $object_type |
  "OperatorCap:\n  Object ID: \($object_id)\n  Type: \($object_type)\n---"'

echo ""
echo "=== Summary ==="
echo "Address: $ADDRESS"
echo "Total OperatorCap objects: $CAP_COUNT"
echo ""
echo "To use an OperatorCap in transactions, use its Object ID."

