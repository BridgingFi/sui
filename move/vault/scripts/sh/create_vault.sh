#!/bin/bash

# Script to create vault and reward manager
# Usage: ./create_vault.sh [COIN_TYPE]

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

COIN_TYPE=${1:-$COIN_TYPE}

if [ -z "$COIN_TYPE" ]; then
  echo "Error: COIN_TYPE is not set. Set it as environment variable or pass as argument:"
  echo "  export COIN_TYPE=0x...::usdc::USDC"
  echo "  or: $0 0x...::usdc::USDC"
  exit 1
fi

# Get the active address
WALLET_ADDRESS=$(sui client active-address | grep -o '0x[0-9a-fA-F]\+')

if [ -z "$WALLET_ADDRESS" ]; then
  echo "Error: No active address found."
  exit 1
fi

if [ -z "$VOLO_VAULT_PACKAGE_ID" ]; then
  echo "Error: VOLO_VAULT_PACKAGE_ID is not set. Set it as environment variable:"
  echo "  export VOLO_VAULT_PACKAGE_ID=0x..."
  exit 1
fi

if [ -z "$ADMIN_CAP_ID" ]; then
  echo "Error: ADMIN_CAP_ID is not set. Set it as environment variable:"
  echo "  export ADMIN_CAP_ID=0x..."
  exit 1
fi

echo "Volo Vault Package ID: $VOLO_VAULT_PACKAGE_ID"
echo "Admin Cap ID: $ADMIN_CAP_ID"

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Step 1: Create vault
echo ""
echo "Step 1: Creating vault..."
VAULT_TX_JSON=$(sui client call \
  --package "$VOLO_VAULT_PACKAGE_ID" \
  --module vault \
  --function create_vault \
  --type-args "$COIN_TYPE" \
  --args "$ADMIN_CAP_ID" \
  --gas-budget 100000000 \
  --json)

# Check for errors
if echo "$VAULT_TX_JSON" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error during transaction:"
  echo "$VAULT_TX_JSON" | jq '.'
  exit 1
fi

# Display formatted output
echo ""
echo "Transaction details:"
echo "$VAULT_TX_JSON" | jq '{
  digest: .digest,
  effects: .effects.status,
  created: [.objectChanges[] | select(.type == "created") | {objectId: .objectId, objectType: .objectType}]
}'

# Extract vault ID from created objects
VAULT_ID=$(echo "$VAULT_TX_JSON" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("Vault")) | .objectId')

if [ -z "$VAULT_ID" ] || [ "$VAULT_ID" = "null" ]; then
  # Fallback: get first created object
  VAULT_ID=$(echo "$VAULT_TX_JSON" | jq -r '.objectChanges[] | select(.type == "created") | .objectId' | head -1)
fi

if [ -z "$VAULT_ID" ] || [ "$VAULT_ID" = "null" ]; then
  echo "Error: Failed to extract vault ID from transaction output."
  echo "Full transaction output:"
  echo "$VAULT_TX_JSON" | jq '.'
  exit 1
fi

echo ""
echo "Vault created successfully!"
echo "Vault ID: $VAULT_ID"

# Step 2: Create reward manager
echo ""
echo "Step 2: Creating reward manager..."
REWARD_MANAGER_TX_JSON=$(sui client call \
  --package "$VOLO_VAULT_PACKAGE_ID" \
  --module vault_manage \
  --function create_reward_manager \
  --type-args "$COIN_TYPE" \
  --args "$ADMIN_CAP_ID" "$VAULT_ID" \
  --gas-budget 100000000 \
  --json)

# Check for errors
if echo "$REWARD_MANAGER_TX_JSON" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error during transaction:"
  echo "$REWARD_MANAGER_TX_JSON" | jq '.'
  exit 1
fi

# Display formatted output
echo ""
echo "Transaction details:"
echo "$REWARD_MANAGER_TX_JSON" | jq '{
  digest: .digest,
  effects: .effects.status,
  created: [.objectChanges[] | select(.type == "created") | {objectId: .objectId, objectType: .objectType}]
}'

# Extract reward manager ID from created objects
REWARD_MANAGER_ID=$(echo "$REWARD_MANAGER_TX_JSON" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("RewardManager")) | .objectId')

if [ -z "$REWARD_MANAGER_ID" ] || [ "$REWARD_MANAGER_ID" = "null" ]; then
  # Fallback: get first created object
  REWARD_MANAGER_ID=$(echo "$REWARD_MANAGER_TX_JSON" | jq -r '.objectChanges[] | select(.type == "created") | .objectId' | head -1)
fi

if [ -z "$REWARD_MANAGER_ID" ] || [ "$REWARD_MANAGER_ID" = "null" ]; then
  echo "Error: Failed to extract reward manager ID from transaction output."
  echo "Full transaction output:"
  echo "$REWARD_MANAGER_TX_JSON" | jq '.'
  exit 1
fi

echo ""
echo "Reward Manager created successfully!"
echo "Reward Manager ID: $REWARD_MANAGER_ID"

echo ""
echo "=== Summary ==="
echo "Vault ID: $VAULT_ID"
echo "Reward Manager ID: $REWARD_MANAGER_ID"
echo ""
echo "Next step: Register the vault to the registry using:"
echo "  ./register_vault.sh $VAULT_ID $REWARD_MANAGER_ID"

