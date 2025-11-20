#!/bin/bash

# Script to query deposit and withdraw requests from a vault
# Uses sui client dynamic-field to list all pending requests
#
# Usage:
#   ./query_vault_requests.sh <VAULT_ID>
#
# Arguments:
#   - VAULT_ID: The vault object ID
#
# Example:
#   ./query_vault_requests.sh 0xdf389ffc402bdd678e926e69ff2478f7915273aad8b1b165c07763fa4f9a42b2

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

VAULT_ID=${1:-""}

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

if [ -z "$VAULT_ID" ]; then
  echo "Error: VAULT_ID is required."
  echo "Usage: $0 <VAULT_ID>"
  echo "  or set VAULT_ID environment variable"
  exit 1
fi

echo "Querying Vault Requests"
echo "Vault ID: $VAULT_ID"
echo ""

# Get vault object to extract request_buffer (internal structure)
VAULT_DATA=$(sui client object "$VAULT_ID" --json 2>/dev/null)

if echo "$VAULT_DATA" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error: Could not query vault object: $VAULT_ID"
  echo "$VAULT_DATA" | jq '.error'
  exit 1
fi

# Extract request_buffer fields (internal structure that stores requests)
REQUEST_BUFFER=$(echo "$VAULT_DATA" | jq '.content.fields.request_buffer // .data.content.fields.request_buffer // empty')

if [ "$REQUEST_BUFFER" = "null" ] || [ -z "$REQUEST_BUFFER" ]; then
  echo "Error: Could not extract requests from vault object."
  echo "Vault data:"
  echo "$VAULT_DATA" | jq '.'
  exit 1
fi

# Extract deposit and withdraw info
DEPOSIT_REQUESTS_TABLE=$(echo "$REQUEST_BUFFER" | jq '.fields.deposit_requests // empty')
WITHDRAW_REQUESTS_TABLE=$(echo "$REQUEST_BUFFER" | jq '.fields.withdraw_requests // empty')

# Extract table IDs
DEPOSIT_REQUESTS_TABLE_ID=$(echo "$DEPOSIT_REQUESTS_TABLE" | jq -r '.fields.id.id // empty')
WITHDRAW_REQUESTS_TABLE_ID=$(echo "$WITHDRAW_REQUESTS_TABLE" | jq -r '.fields.id.id // empty')
DEPOSIT_REQUESTS_SIZE=$(echo "$DEPOSIT_REQUESTS_TABLE" | jq -r '.fields.size // "0"')
WITHDRAW_REQUESTS_SIZE=$(echo "$WITHDRAW_REQUESTS_TABLE" | jq -r '.fields.size // "0"')

if [ -z "$DEPOSIT_REQUESTS_TABLE_ID" ] || [ "$DEPOSIT_REQUESTS_TABLE_ID" = "null" ]; then
  echo "Error: Could not extract deposit_requests table ID."
  exit 1
fi

if [ -z "$WITHDRAW_REQUESTS_TABLE_ID" ] || [ "$WITHDRAW_REQUESTS_TABLE_ID" = "null" ]; then
  echo "Error: Could not extract withdraw_requests table ID."
  exit 1
fi

# Step 2: Query dynamic fields for deposit requests
echo "=== Deposit Requests ($DEPOSIT_REQUESTS_SIZE) ==="
if [ "$DEPOSIT_REQUESTS_SIZE" = "0" ] || [ "$DEPOSIT_REQUESTS_SIZE" = "null" ]; then
  echo "No deposit requests found."
else
  DEPOSIT_DYNAMIC_FIELDS=$(sui client dynamic-field "$DEPOSIT_REQUESTS_TABLE_ID" --json 2>/dev/null)
  
  if echo "$DEPOSIT_DYNAMIC_FIELDS" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error querying deposit requests:"
    echo "$DEPOSIT_DYNAMIC_FIELDS" | jq '.error'
  else
    DEPOSIT_FIELDS_DATA=$(echo "$DEPOSIT_DYNAMIC_FIELDS" | jq '.data // []')
    DEPOSIT_COUNT=$(echo "$DEPOSIT_FIELDS_DATA" | jq 'length')
    
    if [ "$DEPOSIT_COUNT" = "0" ]; then
      echo "No deposit requests found in dynamic fields."
    else
      # Process each deposit request and query details
      echo "$DEPOSIT_FIELDS_DATA" | jq -r '.[] | .objectId' | while read -r object_id; do
        if [ -n "$object_id" ] && [ "$object_id" != "null" ]; then
          REQUEST_DATA=$(sui client object "$object_id" --json 2>/dev/null)
          
          if ! echo "$REQUEST_DATA" | jq -e '.error' > /dev/null 2>&1; then
            # Extract request details
            REQUEST_ID=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.request_id // .data.content.fields.value.fields.request_id // "N/A"')
            RECEIPT_ID=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.receipt_id // .data.content.fields.value.fields.receipt_id // "N/A"')
            RECIPIENT=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.recipient // .data.content.fields.value.fields.recipient // "N/A"')
            AMOUNT=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.amount // .data.content.fields.value.fields.amount // "0"')
            EXPECTED_SHARES=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.expected_shares // .data.content.fields.value.fields.expected_shares // "0"')
            REQUEST_TIME=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.request_time // .data.content.fields.value.fields.request_time // "0"')
            
            # Convert timestamp to readable date if possible
            if [ "$REQUEST_TIME" != "0" ] && [ "$REQUEST_TIME" != "null" ] && [ "$REQUEST_TIME" != "N/A" ]; then
              REQUEST_DATE=$(date -d "@$((REQUEST_TIME / 1000))" 2>/dev/null || echo "N/A")
              REQUEST_TIME_DISPLAY="$REQUEST_TIME ($REQUEST_DATE)"
            else
              REQUEST_TIME_DISPLAY="$REQUEST_TIME"
            fi
            
            echo "Request ID: $REQUEST_ID"
            echo "  Receipt ID: $RECEIPT_ID"
            echo "  Recipient: $RECIPIENT"
            echo "  Amount: $AMOUNT"
            echo "  Expected Shares: $EXPECTED_SHARES"
            echo "  Request Time: $REQUEST_TIME_DISPLAY"
            echo "  Object ID: $object_id"
            echo "---"
          fi
        fi
      done
    fi
  fi
fi

echo ""

# Step 3: Query dynamic fields for withdraw requests
echo ""
echo "=== Withdraw Requests ($WITHDRAW_REQUESTS_SIZE) ==="
if [ "$WITHDRAW_REQUESTS_SIZE" = "0" ] || [ "$WITHDRAW_REQUESTS_SIZE" = "null" ]; then
  echo "No withdraw requests found."
else
  WITHDRAW_DYNAMIC_FIELDS=$(sui client dynamic-field "$WITHDRAW_REQUESTS_TABLE_ID" --json 2>/dev/null)
  
  if echo "$WITHDRAW_DYNAMIC_FIELDS" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error querying withdraw requests:"
    echo "$WITHDRAW_DYNAMIC_FIELDS" | jq '.error'
  else
    WITHDRAW_FIELDS_DATA=$(echo "$WITHDRAW_DYNAMIC_FIELDS" | jq '.data // []')
    WITHDRAW_COUNT=$(echo "$WITHDRAW_FIELDS_DATA" | jq 'length')
    
    if [ "$WITHDRAW_COUNT" = "0" ]; then
      echo "No withdraw requests found in dynamic fields."
    else
      # Process each withdraw request and query details
      echo "$WITHDRAW_FIELDS_DATA" | jq -r '.[] | .objectId' | while read -r object_id; do
        if [ -n "$object_id" ] && [ "$object_id" != "null" ]; then
          REQUEST_DATA=$(sui client object "$object_id" --json 2>/dev/null)
          
          if ! echo "$REQUEST_DATA" | jq -e '.error' > /dev/null 2>&1; then
            # Extract request details
            REQUEST_ID=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.request_id // .data.content.fields.value.fields.request_id // "N/A"')
            RECEIPT_ID=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.receipt_id // .data.content.fields.value.fields.receipt_id // "N/A"')
            RECIPIENT=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.recipient // .data.content.fields.value.fields.recipient // "N/A"')
            SHARES=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.shares // .data.content.fields.value.fields.shares // "0"')
            EXPECTED_AMOUNT=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.expected_amount // .data.content.fields.value.fields.expected_amount // "0"')
            REQUEST_TIME=$(echo "$REQUEST_DATA" | jq -r '.content.fields.value.fields.request_time // .data.content.fields.value.fields.request_time // "0"')
            
            # Convert timestamp to readable date if possible
            if [ "$REQUEST_TIME" != "0" ] && [ "$REQUEST_TIME" != "null" ] && [ "$REQUEST_TIME" != "N/A" ]; then
              REQUEST_DATE=$(date -d "@$((REQUEST_TIME / 1000))" 2>/dev/null || echo "N/A")
              REQUEST_TIME_DISPLAY="$REQUEST_TIME ($REQUEST_DATE)"
            else
              REQUEST_TIME_DISPLAY="$REQUEST_TIME"
            fi
            
            echo "Request ID: $REQUEST_ID"
            echo "  Receipt ID: $RECEIPT_ID"
            echo "  Recipient: $RECIPIENT"
            echo "  Shares: $SHARES"
            echo "  Expected Amount: $EXPECTED_AMOUNT"
            echo "  Request Time: $REQUEST_TIME_DISPLAY"
            echo "  Object ID: $object_id"
            echo "---"
          fi
        fi
      done
    fi
  fi
fi


