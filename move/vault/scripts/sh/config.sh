#!/bin/bash

# Configuration for vault scripts
# Network-specific package IDs and coin types

# Get current network from sui client
get_network() {
  local env=$(sui client active-env 2>/dev/null || echo "")
  case "$env" in
    *testnet*)
      echo "testnet"
      ;;
    *mainnet*)
      echo "mainnet"
      ;;
    *)
      echo "testnet"  # default to testnet
      ;;
  esac
}

# Load configuration based on network
load_config() {
  local network=$(get_network)
  
  case "$network" in
    testnet)
      # Testnet configuration
      export VAULT_PACKAGE_ID="${VAULT_PACKAGE_ID:-0xdb652c1a47f73b3f42dc4d364f0c5e10dab9cecaf8499d2b08fab75b297da6a9}"
      export VOLO_VAULT_PACKAGE_ID="${VOLO_VAULT_PACKAGE_ID:-0xbbd1c5d3373ac836a1150329536654efe5ba7590d11de277590246d487d3257f}"
      export ADMIN_CAP_ID="${ADMIN_CAP_ID:-0x24b4e87bc42e207b4a15a3b01268ced2abb4ca859c24ac92252e14b246c8603a}"
      export REGISTRY_ID="${REGISTRY_ID:-0x4c7f7a9f29e5c2282007bb55da8a334f7e5f64fd4aaa3f8a7f2b3ae61718c9f5}"
      export COIN_TYPE="${COIN_TYPE:-0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC}"
      ;;
    mainnet)
      # Mainnet configuration
      export VAULT_PACKAGE_ID="${VAULT_PACKAGE_ID:-}"
      export VOLO_VAULT_PACKAGE_ID="${VOLO_VAULT_PACKAGE_ID:-}"
      export ADMIN_CAP_ID="${ADMIN_CAP_ID:-}"
      export REGISTRY_ID="${REGISTRY_ID:-}"
      export COIN_TYPE="${COIN_TYPE:-}"  # Set mainnet USDC when available
      ;;
  esac
}
