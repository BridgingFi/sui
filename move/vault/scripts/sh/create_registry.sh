#!/bin/bash

# Script to create vault registry
# Usage: ./create_registry.sh

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"
load_config

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

echo "Creating vault registry..."
echo "Package ID: $VAULT_PACKAGE_ID"
echo "Admin: $WALLET_ADDRESS"

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "Error: jq is required but not installed. Please install jq first."
  exit 1
fi

# Create registry using sui client with JSON output
REGISTRY_TX_JSON=$(sui client call \
  --package "$VAULT_PACKAGE_ID" \
  --module vault_registry \
  --function create_registry \
  --args "$WALLET_ADDRESS" \
  --gas-budget 100000000 \
  --json)

# Check for errors
if echo "$REGISTRY_TX_JSON" | jq -e '.error' > /dev/null 2>&1; then
  echo "Error during transaction:"
  echo "$REGISTRY_TX_JSON" | jq '.'
  exit 1
fi

# Display formatted output (YAML-like format for readability)
echo ""
echo "Transaction details:"
echo "$REGISTRY_TX_JSON" | jq '{
  digest: .digest,
  effects: .effects.status,
  created: [.objectChanges[] | select(.type == "created") | {objectId: .objectId, objectType: .objectType}]
}'

# Extract registry ID from created objects
REGISTRY_ID=$(echo "$REGISTRY_TX_JSON" | jq -r '.objectChanges[] | select(.type == "created") | select(.objectType | contains("VaultRegistry")) | .objectId')

if [ -z "$REGISTRY_ID" ] || [ "$REGISTRY_ID" = "null" ]; then
  # Fallback: get first created object
  REGISTRY_ID=$(echo "$REGISTRY_TX_JSON" | jq -r '.objectChanges[] | select(.type == "created") | .objectId' | head -1)
fi

if [ -z "$REGISTRY_ID" ] || [ "$REGISTRY_ID" = "null" ]; then
  echo ""
  echo "Warning: Failed to extract registry ID from transaction output."
  echo "Full transaction output:"
  echo "$REGISTRY_TX_JSON" | jq '.'
  exit 1
fi

echo ""
echo "Vault registry created successfully!"
echo "Registry ID: $REGISTRY_ID"
echo ""
echo "Save this for later use:"
echo "  export REGISTRY_ID=$REGISTRY_ID"

