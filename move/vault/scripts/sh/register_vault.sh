#!/bin/bash

# Script to register vault to registry
# Usage: ./register_vault.sh <VAULT_ID> <REWARD_MANAGER_ID> [COIN_TYPE]
# Example: ./register_vault.sh 0x123... 0x456...
# COIN_TYPE is optional and will be read from config if not provided

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

VAULT_ID=$1
REWARD_MANAGER_ID=$2
COIN_TYPE=${3:-$COIN_TYPE}

if [ -z "$VAULT_ID" ] || [ -z "$REWARD_MANAGER_ID" ]; then
  echo "Error: VAULT_ID and REWARD_MANAGER_ID are required."
  echo "Usage: $0 <VAULT_ID> <REWARD_MANAGER_ID> [COIN_TYPE]"
  exit 1
fi

if [ -z "$COIN_TYPE" ]; then
  echo "Error: COIN_TYPE is not set. Set it as environment variable or pass as argument:"
  echo "  export COIN_TYPE=0x...::usdc::USDC"
  echo "  or: $0 <VAULT_ID> <REWARD_MANAGER_ID> 0x...::usdc::USDC"
  exit 1
fi

# Get the active address
WALLET_ADDRESS=$(sui client active-address | grep -o '0x[0-9a-fA-F]\+')

if [ -z "$WALLET_ADDRESS" ]; then
  echo "Error: No active address found."
  exit 1
fi

if [ -z "$VAULT_PACKAGE_ID" ]; then
  echo "Error: VAULT_PACKAGE_ID is not set. Set it as environment variable:"
  echo "  export VAULT_PACKAGE_ID=0x..."
  exit 1
fi

if [ -z "$REGISTRY_ID" ]; then
  echo "Error: REGISTRY_ID is not set. Set it as environment variable:"
  echo "  export REGISTRY_ID=0x..."
  exit 1
fi

echo "Package ID: $VAULT_PACKAGE_ID"
echo "Registry ID: $REGISTRY_ID"
echo "Vault ID: $VAULT_ID"
echo "Reward Manager ID: $REWARD_MANAGER_ID"

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Register vault to registry
echo ""
echo "Registering vault to registry..."

# Convert COIN_TYPE string to vector<u8> hex format for Sui CLI
# Sui CLI requires vector<u8> to be passed as a hex string (0x...)
COIN_TYPE_HEX=$(echo -n "$COIN_TYPE" | od -An -tx1 | tr -d ' \n' | sed 's/^/0x/')

REGISTER_TX_JSON=$(sui client call \
  --package "$VAULT_PACKAGE_ID" \
  --module vault_registry \
  --function register_vault_by_id \
  --type-args "$COIN_TYPE" \
  --args "$REGISTRY_ID" "$VAULT_ID" "$REWARD_MANAGER_ID" "$COIN_TYPE_HEX" "0x6" \
  --gas-budget 100000000 \
  --json 2>&1)

# Check if the output is valid JSON (success) or error message
if ! echo "$REGISTER_TX_JSON" | jq empty 2>/dev/null; then
  echo "Error during transaction:"
  echo "$REGISTER_TX_JSON"
  exit 1
fi

# Check for errors in JSON response
if echo "$REGISTER_TX_JSON" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error during transaction:"
  echo "$REGISTER_TX_JSON" | jq '.'
  exit 1
fi

# Display formatted output
echo ""
echo "Transaction details:"
echo "$REGISTER_TX_JSON" | jq '{
  digest: .digest,
  effects: .effects.status,
  events: [.events[] | {type: .type, parsedJson: .parsedJson}]
}'

echo ""
echo "Vault registered successfully!"

