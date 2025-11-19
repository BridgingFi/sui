#!/bin/bash

# Script to query receipt objects
# Usage: ./query_receipts.sh [OWNER_ADDRESS] [VAULT_ID]
#   - If no OWNER_ADDRESS is provided: uses active-address
#   - If only OWNER_ADDRESS is provided: shows all receipts owned by the address
#   - If OWNER_ADDRESS and VAULT_ID are provided: shows receipts for that vault

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

OWNER_ADDRESS=${1:-""}
VAULT_ID=$2

# If no owner address provided, use active address
if [ -z "$OWNER_ADDRESS" ]; then
  OWNER_ADDRESS=$(sui client active-address 2>/dev/null || echo "")
  if [ -z "$OWNER_ADDRESS" ]; then
    echo "Error: No OWNER_ADDRESS provided and no active address found."
    echo "Usage: $0 [OWNER_ADDRESS] [VAULT_ID]"
    echo "  or set active address: sui client switch --address <ADDRESS>"
    exit 1
  fi
  echo "Using active address: $OWNER_ADDRESS"
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi


if [ -z "$VOLO_VAULT_PACKAGE_ID" ]; then
  echo "Error: VOLO_VAULT_PACKAGE_ID is not set. Set it as environment variable:"
  echo "  export VOLO_VAULT_PACKAGE_ID=0x..."
  exit 1
fi

echo "Querying receipts for owner: $OWNER_ADDRESS"
if [ -n "$VAULT_ID" ]; then
  echo "Filtering by vault: $VAULT_ID"
fi
echo "Volo Vault Package ID: $VOLO_VAULT_PACKAGE_ID"
echo ""

# Query all receipt objects owned by the address
RECEIPT_TYPE="${VOLO_VAULT_PACKAGE_ID}::receipt::Receipt"
echo "=== Querying Receipt Objects ==="
echo "Receipt Type: $RECEIPT_TYPE"
echo ""

# Query all objects owned by the address
ALL_OBJECTS=$(sui client objects "$OWNER_ADDRESS" --json 2>/dev/null)

# Check for errors
if echo "$ALL_OBJECTS" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error querying objects:"
  echo "$ALL_OBJECTS" | jq '.error'
  exit 1
fi

# Filter receipts by type
# sui client objects returns array format: [{data: {...}}, ...]
RECEIPTS_ARRAY=$(echo "$ALL_OBJECTS" | jq --arg receipt_type "$RECEIPT_TYPE" '[.[]? | select(.data.type? == $receipt_type)]')


if [ -z "$RECEIPTS_ARRAY" ] || [ "$RECEIPTS_ARRAY" = "[]" ]; then
  echo "No receipts found for owner: $OWNER_ADDRESS"
  exit 0
fi

# Filter by vault_id if provided
if [ -n "$VAULT_ID" ]; then
  RECEIPTS_ARRAY=$(echo "$RECEIPTS_ARRAY" | jq --arg vault_id "$VAULT_ID" '[.[] | select(.data.content.fields.vault_id == $vault_id)]')
fi

RECEIPT_COUNT=$(echo "$RECEIPTS_ARRAY" | jq 'length')

if [ "$RECEIPT_COUNT" = "0" ]; then
  echo "No receipts found matching the criteria."
  exit 0
fi

echo "Found $RECEIPT_COUNT receipt(s)"
echo ""

# Show all receipts
echo "=== All Receipts ==="
echo ""

echo "$RECEIPTS_ARRAY" | jq -r '.[] | 
  . as $receipt |
  ($receipt.data.objectId) as $receipt_id |
  ($receipt.data.content.fields.vault_id // "N/A") as $vault_id |
  "Receipt ID: \($receipt_id)\n" +
  "  Vault ID: \($vault_id)\n" +
  "  Object Type: \($receipt.data.type // "N/A")\n" +
  "  Owner: \($receipt.data.owner.AddressOwner // $receipt.data.owner.ObjectOwner // "N/A")\n" +
  "  Version: \($receipt.data.version // "N/A")\n" +
  "  Digest: \($receipt.data.digest // "N/A")\n" +
  "  Fields: \($receipt.data.content.fields | tostring)\n"'

