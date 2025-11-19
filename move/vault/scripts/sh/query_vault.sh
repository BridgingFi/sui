#!/bin/bash

# Script to query vault information
# Usage: ./query_vault.sh <VAULT_ID>
#   - VAULT_ID: The vault object ID
#   Note: Coin type is automatically extracted from the vault object's type

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

if [ -z "$VOLO_VAULT_PACKAGE_ID" ]; then
  echo "Error: VOLO_VAULT_PACKAGE_ID is not set. Set it as environment variable:"
  echo "  export VOLO_VAULT_PACKAGE_ID=0x..."
  exit 1
fi

echo "Querying vault: $VAULT_ID"
echo "Volo Vault Package ID: $VOLO_VAULT_PACKAGE_ID"
echo ""

# Query vault object to get basic fields
echo "=== Vault Object Fields ==="
VAULT_DATA=$(sui client object "$VAULT_ID" --json)

# Check for errors
if echo "$VAULT_DATA" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error querying vault:"
  echo "$VAULT_DATA" | jq '.error'
  exit 1
fi

# Extract vault fields
CONTENT=$(echo "$VAULT_DATA" | jq '.content // .data.content // empty')

if [ "$CONTENT" = "null" ] || [ -z "$CONTENT" ]; then
  echo "Error: Could not retrieve vault object content."
  echo "Full response:"
  echo "$VAULT_DATA" | jq '.'
  exit 1
fi

# Extract coin type from vault object type
# Type format: 0x...::vault::Vault<0x...::usdc::USDC>
VAULT_TYPE=$(echo "$VAULT_DATA" | jq -r '.data.type // .type // empty')
COIN_TYPE=""

if [ -n "$VAULT_TYPE" ] && [ "$VAULT_TYPE" != "null" ]; then
  # Extract type argument from generic type using sed
  COIN_TYPE=$(echo "$VAULT_TYPE" | sed -n 's/.*<\([^>]*\)>.*/\1/p')
  echo "Vault Type: $VAULT_TYPE"
  if [ -n "$COIN_TYPE" ]; then
    echo "Coin Type (extracted): $COIN_TYPE"
  fi
  echo ""
fi

# Extract fields from vault object
FIELDS=$(echo "$VAULT_DATA" | jq '.content.fields // .data.content.fields // empty')

if [ "$FIELDS" != "null" ] && [ -n "$FIELDS" ]; then
  echo "Vault Fields:"
  echo "$FIELDS" | jq '{
    deposit_fee_rate: .deposit_fee_rate,
    withdraw_fee_rate: .withdraw_fee_rate,
    total_shares: .total_shares,
    status: .status,
    version: .version
  }'
  echo ""
fi

# Query share_ratio from ShareRatioUpdated events
if [ -n "$COIN_TYPE" ]; then
  echo "=== Querying Share Ratio ==="
  EVENT_TYPE="${VOLO_VAULT_PACKAGE_ID}::vault::ShareRatioUpdated"
  
  echo "Querying ShareRatioUpdated events..."
  EVENTS_JSON=$(sui client query-events \
    --query "MoveEvent=$EVENT_TYPE" \
    --limit 50 \
    --json 2>/dev/null || echo '{"data":[]}')
  
  SHARE_RATIO_FROM_EVENT=""
  
  if echo "$EVENTS_JSON" | jq -e '.error' > /dev/null 2>&1; then
    echo "  Error querying events:"
    echo "$EVENTS_JSON" | jq -r '.error.message // .error'
    echo ""
    echo "  Share Ratio: N/A (query failed)"
  else
    EVENTS_DATA=$(echo "$EVENTS_JSON" | jq '.data // empty')
    
    if [ "$EVENTS_DATA" != "null" ] && [ -n "$EVENTS_DATA" ] && [ "$EVENTS_DATA" != "[]" ]; then
      # Find the latest event for this vault
      LATEST_EVENT=$(echo "$EVENTS_DATA" | jq --arg vault_id "$VAULT_ID" '
        [.[] | select(.parsedJson.vault_id == $vault_id)] | 
        sort_by(.timestampMs // 0) | 
        reverse | 
        .[0] // empty
      ')
      
      if [ -n "$LATEST_EVENT" ] && [ "$LATEST_EVENT" != "null" ]; then
        SHARE_RATIO_FROM_EVENT=$(echo "$LATEST_EVENT" | jq -r '.parsedJson.share_ratio // empty')
        EVENT_TIMESTAMP=$(echo "$LATEST_EVENT" | jq -r '.timestampMs // empty')
        
        if [ -n "$SHARE_RATIO_FROM_EVENT" ] && [ "$SHARE_RATIO_FROM_EVENT" != "null" ]; then
          echo "  ✓ Found share ratio from event:"
          echo "    Share Ratio: $SHARE_RATIO_FROM_EVENT"
          if [ -n "$EVENT_TIMESTAMP" ] && [ "$EVENT_TIMESTAMP" != "null" ] && [ "$EVENT_TIMESTAMP" != "0" ]; then
            EVENT_DATE=$(date -d "@$((EVENT_TIMESTAMP / 1000))" 2>/dev/null || echo "N/A")
            echo "    Timestamp: $EVENT_TIMESTAMP ($EVENT_DATE)"
          fi
        else
          echo "  Share Ratio: N/A (event data incomplete)"
        fi
      else
        echo "  Share Ratio: N/A (no events found for this vault)"
        echo "  Note: Events are only emitted when deposits/withdrawals occur"
      fi
    else
      echo "  Share Ratio: N/A (no events found)"
      echo "  Note: Events are only emitted when get_share_ratio(clock) is called"
      echo "        (e.g., during deposits or withdrawals)"
    fi
  fi
  
  echo ""
else
  echo "Note: Could not extract COIN_TYPE from vault type, skipping share_ratio query."
  echo "Vault type: $VAULT_TYPE"
fi

echo ""
echo "=== Summary ==="
if [ "$FIELDS" != "null" ] && [ -n "$FIELDS" ]; then
  DEPOSIT_FEE_RATE=$(echo "$FIELDS" | jq -r '.deposit_fee_rate // "N/A"')
  WITHDRAW_FEE_RATE=$(echo "$FIELDS" | jq -r '.withdraw_fee_rate // "N/A"')
  TOTAL_SHARES=$(echo "$FIELDS" | jq -r '.total_shares // "N/A"')
  VAULT_STATUS=$(echo "$FIELDS" | jq -r '.status // "N/A"')
  VAULT_VERSION=$(echo "$FIELDS" | jq -r '.version // "N/A"')
  
  echo "Vault ID: $VAULT_ID"
  if [ -n "$COIN_TYPE" ]; then
    echo "Coin Type: $COIN_TYPE"
  fi
  echo ""
  
  echo "Fees:"
  if [ "$DEPOSIT_FEE_RATE" != "N/A" ] && [ "$DEPOSIT_FEE_RATE" != "null" ]; then
    # Calculate percentage: fee_rate / 100
    # Use awk if bc is not available
    if command -v bc &> /dev/null; then
      FEE_PERCENT=$(echo "scale=4; $DEPOSIT_FEE_RATE / 100" | bc 2>/dev/null)
    else
      FEE_PERCENT=$(awk "BEGIN {printf \"%.4f\", $DEPOSIT_FEE_RATE / 100}")
    fi
    if [ -n "$FEE_PERCENT" ]; then
      echo "  Deposit Fee Rate: ${FEE_PERCENT}% ($DEPOSIT_FEE_RATE bp)"
    else
      echo "  Deposit Fee Rate: $DEPOSIT_FEE_RATE bp"
    fi
  else
    echo "  Deposit Fee Rate: N/A"
  fi
  
  if [ "$WITHDRAW_FEE_RATE" != "N/A" ] && [ "$WITHDRAW_FEE_RATE" != "null" ]; then
    if command -v bc &> /dev/null; then
      WITHDRAW_FEE_PERCENT=$(echo "scale=4; $WITHDRAW_FEE_RATE / 100" | bc 2>/dev/null)
    else
      WITHDRAW_FEE_PERCENT=$(awk "BEGIN {printf \"%.4f\", $WITHDRAW_FEE_RATE / 100}")
    fi
    if [ -n "$WITHDRAW_FEE_PERCENT" ]; then
      echo "  Withdraw Fee Rate: ${WITHDRAW_FEE_PERCENT}% ($WITHDRAW_FEE_RATE bp)"
    else
      echo "  Withdraw Fee Rate: $WITHDRAW_FEE_RATE bp"
    fi
  else
    echo "  Withdraw Fee Rate: N/A"
  fi
  
  echo ""
  echo "Vault Status:"
  echo "  Total Shares: $TOTAL_SHARES"
  echo "  Status: $VAULT_STATUS"
  echo "  Version: $VAULT_VERSION"
  
  if [ -n "$SHARE_RATIO_FROM_EVENT" ] && [ "$SHARE_RATIO_FROM_EVENT" != "null" ]; then
    echo ""
    echo "Share Ratio:"
    echo "  $SHARE_RATIO_FROM_EVENT (from events)"
  else
    echo ""
    echo "Share Ratio: N/A (no events found)"
  fi
fi

echo ""
echo "=== Notes ==="
echo "- deposit_fee_rate is in basis points (bp), where 10 bp = 0.1%"
echo "- share_ratio is queried from ShareRatioUpdated events"
echo "  - Events are only emitted when get_share_ratio(clock) is called"
echo "    (e.g., during deposits or withdrawals)"
echo "  - If no events exist, share_ratio will show as N/A (this is normal for new vaults)"
echo "- For real-time share_ratio queries (without events), use the TypeScript SDK:"
echo "  - useVaultInfo hook in web/src/hooks/useVaultInfo.ts"
echo "  - Uses devInspectTransactionBlock for real-time queries"

