#!/bin/bash

# Script to query VaultReceiptInfo for a specific receipt_id from a vault
# Uses RPC suix_getDynamicFieldObject to query the receipts table
#
# Usage:
#   ./query_receipt_info.sh <VAULT_ID> <RECEIPT_ID>
#   ./query_receipt_info.sh <RECEIPT_ID>  (auto-detects VAULT_ID from receipt object)
#
# Arguments:
#   - VAULT_ID: The vault object ID (optional if RECEIPT_ID is provided)
#   - RECEIPT_ID: The receipt address (used as key in receipts table)
#
# Example:
#   ./query_receipt_info.sh 0xb4cf2caaaec79fde1afd96e66a9a4abbc398c8f242219fc209cb0b02f7252f85

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

VAULT_ID=${1:-""}
RECEIPT_ID=${2:-""}

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
  echo "Error: curl is required but not installed. Please install curl first."
  exit 1
fi

# If only one argument provided, treat it as RECEIPT_ID and try to get VAULT_ID from receipt
if [ -n "$VAULT_ID" ] && [ -z "$RECEIPT_ID" ]; then
  RECEIPT_ID="$VAULT_ID"
  VAULT_ID=""
fi

# If RECEIPT_ID is provided but VAULT_ID is not, try to get VAULT_ID from receipt object
if [ -n "$RECEIPT_ID" ] && [ -z "$VAULT_ID" ]; then
  echo "VAULT_ID not provided, attempting to get it from receipt object..."
  RECEIPT_DATA=$(sui client object "$RECEIPT_ID" --json 2>/dev/null)
  
  if echo "$RECEIPT_DATA" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error: Could not query receipt object: $RECEIPT_ID"
    echo "$RECEIPT_DATA" | jq '.error'
    echo ""
    echo "Please provide both VAULT_ID and RECEIPT_ID:"
    echo "Usage: $0 <VAULT_ID> <RECEIPT_ID>"
    echo "  or: $0 <RECEIPT_ID>  (will auto-detect VAULT_ID from receipt)"
    exit 1
  fi
  
  VAULT_ID=$(echo "$RECEIPT_DATA" | jq -r '.content.fields.vault_id // .data.content.fields.vault_id // empty')
  
  if [ -z "$VAULT_ID" ] || [ "$VAULT_ID" = "null" ]; then
    echo "Error: Could not extract vault_id from receipt object."
    echo "Receipt data:"
    echo "$RECEIPT_DATA" | jq '.'
    exit 1
  fi
  
  echo "Found VAULT_ID from receipt: $VAULT_ID"
  echo ""
fi

if [ -z "$VAULT_ID" ]; then
  echo "Error: VAULT_ID is required."
  echo "Usage: $0 <VAULT_ID> <RECEIPT_ID>"
  echo "  or: $0 <RECEIPT_ID>  (will auto-detect VAULT_ID from receipt)"
  echo "  or set VAULT_ID environment variable"
  exit 1
fi

if [ -z "$RECEIPT_ID" ]; then
  echo "Error: RECEIPT_ID is required."
  echo "Usage: $0 <VAULT_ID> <RECEIPT_ID>"
  echo "  or: $0 <RECEIPT_ID>  (will auto-detect VAULT_ID from receipt)"
  exit 1
fi

# Get RPC URL from active environment
ACTIVE_ENV=$(sui client active-env 2>/dev/null || echo "testnet")
case "$ACTIVE_ENV" in
  *testnet*)
    RPC_URL="https://fullnode.testnet.sui.io:443"
    ;;
  *mainnet*)
    RPC_URL="https://fullnode.mainnet.sui.io:443"
    ;;
  *devnet*)
    RPC_URL="https://fullnode.devnet.sui.io:443"
    ;;
  *)
    RPC_URL="https://fullnode.testnet.sui.io:443"
    echo "Warning: Unknown environment, defaulting to testnet RPC"
    ;;
esac

echo "Querying VaultReceiptInfo"
echo "Vault ID: $VAULT_ID"
echo "Receipt ID: $RECEIPT_ID"
echo "RPC URL: $RPC_URL"
echo ""

# First, get the receipts table ID from the vault object
echo "Step 1: Getting receipts table ID from vault..."
VAULT_DATA=$(sui client object "$VAULT_ID" --json 2>/dev/null)

if echo "$VAULT_DATA" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error: Could not query vault object: $VAULT_ID"
  echo "$VAULT_DATA" | jq '.error'
  exit 1
fi

RECEIPTS_TABLE_ID=$(echo "$VAULT_DATA" | jq -r '.content.fields.receipts.fields.id.id // .data.content.fields.receipts.fields.id.id // empty')

if [ -z "$RECEIPTS_TABLE_ID" ] || [ "$RECEIPTS_TABLE_ID" = "null" ]; then
  echo "Error: Could not extract receipts table ID from vault object."
  echo "Vault data:"
  echo "$VAULT_DATA" | jq '.'
  exit 1
fi

echo "Receipts Table ID: $RECEIPTS_TABLE_ID"
echo ""

# Call RPC to get dynamic field object from the Table
echo "Step 2: Querying dynamic field from receipts table..."
RPC_RESPONSE=$(curl -s -X POST "$RPC_URL" \
  -H "Content-Type: application/json" \
  -d "{
    \"jsonrpc\": \"2.0\",
    \"id\": 1,
    \"method\": \"suix_getDynamicFieldObject\",
    \"params\": [
      \"$RECEIPTS_TABLE_ID\",
      {
        \"type\": \"address\",
        \"value\": \"$RECEIPT_ID\"
      }
    ]
  }")

# Check for RPC errors
if echo "$RPC_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error from RPC:"
  echo "$RPC_RESPONSE" | jq '.error'
  exit 1
fi

# Check if result exists
RESULT=$(echo "$RPC_RESPONSE" | jq '.result // empty')

if [ "$RESULT" = "null" ] || [ -z "$RESULT" ]; then
  echo "Error: No dynamic field found for receipt_id: $RECEIPT_ID"
  echo "This could mean:"
  echo "  1. The receipt_id does not exist in the vault's receipts table"
  echo "  2. The vault_id is incorrect"
  echo "  3. The receipt_id format is incorrect"
  exit 1
fi

# Extract object data
OBJECT_DATA=$(echo "$RESULT" | jq '.data // empty')

if [ "$OBJECT_DATA" = "null" ] || [ -z "$OBJECT_DATA" ]; then
  echo "Error: Dynamic field exists but has no data"
  echo "Full response:"
  echo "$RPC_RESPONSE" | jq '.'
  exit 1
fi

# Extract content
CONTENT=$(echo "$OBJECT_DATA" | jq '.content // empty')

if [ "$CONTENT" = "null" ] || [ -z "$CONTENT" ]; then
  echo "Error: Could not retrieve object content."
  echo "Full response:"
  echo "$RPC_RESPONSE" | jq '.'
  exit 1
fi

# Check if it's a Move object
DATA_TYPE=$(echo "$CONTENT" | jq -r '.dataType // empty')

if [ "$DATA_TYPE" != "moveObject" ]; then
  echo "Error: Expected moveObject, got: $DATA_TYPE"
  echo "Full response:"
  echo "$RPC_RESPONSE" | jq '.'
  exit 1
fi

# Extract fields
FIELDS=$(echo "$CONTENT" | jq '.fields // empty')

if [ "$FIELDS" = "null" ] || [ -z "$FIELDS" ]; then
  echo "Error: Could not extract fields from object."
  echo "Full response:"
  echo "$RPC_RESPONSE" | jq '.'
  exit 1
fi

# Extract VaultReceiptInfo fields
# Note: The dynamic field structure is: { name: address, value: VaultReceiptInfo }
# So we need to extract .value.fields
VALUE_FIELDS=$(echo "$FIELDS" | jq '.value.fields // .fields // empty')

if [ "$VALUE_FIELDS" = "null" ] || [ -z "$VALUE_FIELDS" ]; then
  # Try direct fields if value.fields doesn't exist
  VALUE_FIELDS="$FIELDS"
fi

echo "=== VaultReceiptInfo ==="
echo ""

# Parse and display fields
STATUS=$(echo "$VALUE_FIELDS" | jq -r '.status // 0')
SHARES=$(echo "$VALUE_FIELDS" | jq -r '.shares // "0"')
PENDING_DEPOSIT_BALANCE=$(echo "$VALUE_FIELDS" | jq -r '.pending_deposit_balance // 0')
PENDING_WITHDRAW_SHARES=$(echo "$VALUE_FIELDS" | jq -r '.pending_withdraw_shares // "0"')
LAST_DEPOSIT_TIME=$(echo "$VALUE_FIELDS" | jq -r '.last_deposit_time // 0')
CLAIMABLE_PRINCIPAL=$(echo "$VALUE_FIELDS" | jq -r '.claimable_principal // 0')

# Status mapping
case "$STATUS" in
  0)
    STATUS_TEXT="NORMAL"
    ;;
  1)
    STATUS_TEXT="PENDING_DEPOSIT"
    ;;
  2)
    STATUS_TEXT="PENDING_WITHDRAW"
    ;;
  3)
    STATUS_TEXT="PENDING_WITHDRAW_WITH_AUTO_TRANSFER"
    ;;
  *)
    STATUS_TEXT="UNKNOWN($STATUS)"
    ;;
esac

echo "Status: $STATUS_TEXT ($STATUS)"
echo "Shares: $SHARES"
echo "Pending Deposit Balance: $PENDING_DEPOSIT_BALANCE"
echo "Pending Withdraw Shares: $PENDING_WITHDRAW_SHARES"
echo "Claimable Principal: $CLAIMABLE_PRINCIPAL"

# Convert timestamp to readable date if possible
if [ "$LAST_DEPOSIT_TIME" != "0" ] && [ "$LAST_DEPOSIT_TIME" != "null" ]; then
  LAST_DEPOSIT_DATE=$(date -d "@$((LAST_DEPOSIT_TIME / 1000))" 2>/dev/null || echo "N/A")
  echo "Last Deposit Time: $LAST_DEPOSIT_TIME ($LAST_DEPOSIT_DATE)"
else
  echo "Last Deposit Time: $LAST_DEPOSIT_TIME (never)"
fi

# Display reward tables info (if available)
REWARD_INDICES=$(echo "$VALUE_FIELDS" | jq '.reward_indices // empty')
UNCLAIMED_REWARDS=$(echo "$VALUE_FIELDS" | jq '.unclaimed_rewards // empty')

if [ "$REWARD_INDICES" != "null" ] && [ -n "$REWARD_INDICES" ]; then
  REWARD_INDICES_TABLE_ID=$(echo "$REWARD_INDICES" | jq -r '.fields.id.id // empty')
  REWARD_INDICES_SIZE=$(echo "$REWARD_INDICES" | jq -r '.fields.size // "0"')
  if [ -n "$REWARD_INDICES_TABLE_ID" ] && [ "$REWARD_INDICES_TABLE_ID" != "null" ]; then
    echo ""
    echo "Reward Indices Table ID: $REWARD_INDICES_TABLE_ID (size: $REWARD_INDICES_SIZE)"
  fi
fi

if [ "$UNCLAIMED_REWARDS" != "null" ] && [ -n "$UNCLAIMED_REWARDS" ]; then
  UNCLAIMED_REWARDS_TABLE_ID=$(echo "$UNCLAIMED_REWARDS" | jq -r '.fields.id.id // empty')
  UNCLAIMED_REWARDS_SIZE=$(echo "$UNCLAIMED_REWARDS" | jq -r '.fields.size // "0"')
  if [ -n "$UNCLAIMED_REWARDS_TABLE_ID" ] && [ "$UNCLAIMED_REWARDS_TABLE_ID" != "null" ]; then
    echo ""
    echo "Unclaimed Rewards Table ID: $UNCLAIMED_REWARDS_TABLE_ID (size: $UNCLAIMED_REWARDS_SIZE)"
  fi
fi

