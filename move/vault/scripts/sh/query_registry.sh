#!/bin/bash

# Script to query vault registry
# Usage: ./query_registry.sh [REGISTRY_ID] [VAULT_ID]
#   - If only REGISTRY_ID is provided: shows all vaults in registry
#   - If both REGISTRY_ID and VAULT_ID are provided: shows specific vault info

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

REGISTRY_ID=${1:-$REGISTRY_ID}
VAULT_ID=$2

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

if [ -z "$REGISTRY_ID" ]; then
  echo "Error: REGISTRY_ID is required."
  echo "Usage: $0 [REGISTRY_ID] [VAULT_ID]"
  echo "  or set REGISTRY_ID environment variable"
  exit 1
fi

echo "Querying registry: $REGISTRY_ID"
echo ""

# Get registry object data with all fields
REGISTRY_DATA=$(sui client object "$REGISTRY_ID" --json)

# Check for errors
if echo "$REGISTRY_DATA" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error querying registry:"
  echo "$REGISTRY_DATA" | jq '.error'
  exit 1
fi

# Extract object content - Sui CLI returns .content directly, not .data.content
CONTENT=$(echo "$REGISTRY_DATA" | jq '.content // .data.content // empty')

if [ "$CONTENT" = "null" ] || [ -z "$CONTENT" ]; then
  echo "Error: Could not retrieve registry object content."
  echo "Full response:"
  echo "$REGISTRY_DATA" | jq '.'
  exit 1
fi

# Extract admin address
ADMIN=$(echo "$REGISTRY_DATA" | jq -r '.content.fields.admin // .data.content.fields.admin // empty')

# Extract vaults VecMap - VecMap structure: { fields: { contents: [{ key: address, value: VaultInfo }] } }
VAULTS_MAP=$(echo "$REGISTRY_DATA" | jq '.content.fields.vaults // .data.content.fields.vaults // empty')
VAULTS_CONTENTS=$(echo "$VAULTS_MAP" | jq '.fields.contents // .contents // []')
VAULT_COUNT=$(echo "$VAULTS_CONTENTS" | jq 'length')

# Display registry info
echo "=== Registry Information ==="
echo "Registry ID: $REGISTRY_ID"
echo "Admin: $ADMIN"
echo "Total registered vaults: ${VAULT_COUNT:-0}"
echo ""

if [ "$VAULT_COUNT" = "0" ] || [ -z "$VAULT_COUNT" ] || [ "$VAULT_COUNT" = "null" ]; then
  echo "No vaults registered in this registry."
  exit 0
fi

# VecMap structure: { fields: { contents: [{ key: address, value: VaultInfo }] } }
# If specific vault ID is provided
if [ -n "$VAULT_ID" ]; then
  echo "=== Vault Info: $VAULT_ID ==="
  echo ""
  
  # Find vault entry in contents array
  # VecMap Entry structure: { fields: { key: address, value: VaultInfo } }
  VAULT_ENTRY=$(echo "$VAULTS_CONTENTS" | jq --arg vault_id "$VAULT_ID" '.[] | select(.fields.key == $vault_id)')
  
  if [ -z "$VAULT_ENTRY" ] || [ "$VAULT_ENTRY" = "null" ]; then
    echo "Vault $VAULT_ID not found in registry."
    exit 1
  fi
  
  # Extract vault info from the entry value
  VAULT_VALUE=$(echo "$VAULT_ENTRY" | jq '.fields.value.fields')
  
  # Handle VaultInfo structure
  VAULT_ID_FOUND=$(echo "$VAULT_VALUE" | jq -r '.vault_id // empty')
  REWARD_MANAGER_ID=$(echo "$VAULT_VALUE" | jq -r '.reward_manager_id // empty')
  COIN_TYPE_BYTES=$(echo "$VAULT_VALUE" | jq '.coin_type // empty')
  CREATED_AT_MS=$(echo "$VAULT_VALUE" | jq -r '.created_at_ms // empty')
  CREATOR=$(echo "$VAULT_VALUE" | jq -r '.creator // empty')
  
  # Convert coin_type bytes array to string
  if [ -n "$COIN_TYPE_BYTES" ] && [ "$COIN_TYPE_BYTES" != "null" ]; then
    if echo "$COIN_TYPE_BYTES" | jq -e 'type == "array"' > /dev/null 2>&1; then
      # Convert byte array (numbers) to ASCII string
      COIN_TYPE=$(echo "$COIN_TYPE_BYTES" | jq -r '[.[] | if type == "number" then . else tonumber end] | map([.] | implode) | join("")')
    else
      COIN_TYPE="$COIN_TYPE_BYTES"
    fi
  else
    COIN_TYPE="N/A"
  fi
  
  # Convert timestamp to readable date if possible
  if [ -n "$CREATED_AT_MS" ] && [ "$CREATED_AT_MS" != "null" ] && [ "$CREATED_AT_MS" != "0" ]; then
    CREATED_AT=$(date -d "@$((CREATED_AT_MS / 1000))" 2>/dev/null || echo "${CREATED_AT_MS}ms")
  else
    CREATED_AT="N/A"
  fi
  
  echo "Vault ID: ${VAULT_ID_FOUND:-$VAULT_ID}"
  echo "Reward Manager ID: ${REWARD_MANAGER_ID:-N/A}"
  echo "Coin Type: $COIN_TYPE"
  echo "Created At: $CREATED_AT"
  echo "Creator: ${CREATOR:-N/A}"
else
  # Show all vaults
  echo "=== All Registered Vaults ==="
  echo ""
  
  # Extract all vaults from contents array
  # VecMap Entry structure: { fields: { key: address, value: { fields: VaultInfo } } }
  echo "$VAULTS_CONTENTS" | jq -r '.[] | 
    . as $entry |
    ($entry.fields.value.fields.coin_type | if type == "array" then ([.[] | if type == "number" then . else tonumber end] | map([.] | implode) | join("")) else . end) as $coin_type |
    "Vault ID: \($entry.fields.key)\n" +
    "  Reward Manager: \($entry.fields.value.fields.reward_manager_id // "N/A")\n" +
    "  Coin Type: \($coin_type // "N/A")\n" +
    "  Created At: \($entry.fields.value.fields.created_at_ms // "N/A")ms\n" +
    "  Creator: \($entry.fields.value.fields.creator // "N/A")\n"'
  
  echo ""
  echo "Note: For detailed view of a specific vault, use:"
  echo "  $0 $REGISTRY_ID <VAULT_ID>"
fi
