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
      export VOLO_VAULT_PACKAGE_ID="${VOLO_VAULT_PACKAGE_ID:-0xec71942d8c4cfdc2b509de5c727853cf923ce4fcf6e50098c7dc7753e4c4160e}"
      export VOLO_OPERATION_ID="${VOLO_OPERATION_ID:-0x7c0b4f1e880b6c36bad85fc6e64c383d7900a168c21914551d18c4e7b42996db}"
      export VOLO_ORACLE_CONFIG_ID="${VOLO_ORACLE_CONFIG_ID:-0xee4ea1b690641cbe739b9f54f79d4f93707068cc7d75fe0452c23b8c41857152}"
      export ADMIN_CAP_ID="${ADMIN_CAP_ID:-0x24b4e87bc42e207b4a15a3b01268ced2abb4ca859c24ac92252e14b246c8603a}"
      export REGISTRY_ID="${REGISTRY_ID:-0x4c7f7a9f29e5c2282007bb55da8a334f7e5f64fd4aaa3f8a7f2b3ae61718c9f5}"
      export COIN_TYPE="${COIN_TYPE:-0xea10912247c015ead590e481ae8545ff1518492dee41d6d03abdad828c1d2bde::usdc::USDC}"
      ;;
    mainnet)
      # Mainnet configuration
      export VAULT_PACKAGE_ID="${VAULT_PACKAGE_ID:-}"
      export VOLO_VAULT_PACKAGE_ID="${VOLO_VAULT_PACKAGE_ID:-}"
      export VOLO_OPERATION_ID="${VOLO_OPERATION_ID:-}"
      export VOLO_ORACLE_CONFIG_ID="${VOLO_ORACLE_CONFIG_ID:-}"
      export ADMIN_CAP_ID="${ADMIN_CAP_ID:-}"
      export REGISTRY_ID="${REGISTRY_ID:-}"
      export COIN_TYPE="${COIN_TYPE:-}"  # Set mainnet USDC when available
      ;;
  esac
}

# ---------------------  Command Execution Utilities  ---------------------//

# Global variables for command execution results
_SUI_CMD_STDOUT=""
_SUI_CMD_STDERR=""
_SUI_CMD_EXIT_CODE=0

# Execute a command and capture stdout, stderr, and exit code
# Automatically prints stdout and stderr to stderr if command fails
# Usage: execute_sui_command "command"
# Results are stored in global variables:
#   _SUI_CMD_STDOUT - stdout output
#   _SUI_CMD_STDERR - stderr output
#   _SUI_CMD_EXIT_CODE - exit code
# Returns: exit code of the command (0 = success, non-zero = failure)
execute_sui_command() {
  local cmd="$1"
  local stderr_file=$(mktemp)
  
  _SUI_CMD_STDOUT=$(eval "$cmd" 2>"$stderr_file")
  _SUI_CMD_EXIT_CODE=$?
  _SUI_CMD_STDERR=$(cat "$stderr_file" 2>/dev/null || echo "")
  rm -f "$stderr_file"
  
  # If command failed, automatically print stdout and stderr to stderr
  # Filter out warning messages from stderr
  if [ $_SUI_CMD_EXIT_CODE -ne 0 ]; then
    echo "Command failed: $cmd" >&2
    if [ -n "$_SUI_CMD_STDOUT" ]; then
      echo "Stdout output:" >&2
      echo "$_SUI_CMD_STDOUT" >&2
    fi
    if [ -n "$_SUI_CMD_STDERR" ]; then
      echo "Stderr output:" >&2
      echo "$_SUI_CMD_STDERR" >&2
    fi
  fi
  
  return $_SUI_CMD_EXIT_CODE
}


# Check if Sui command response JSON is valid and contains error field
# Usage: check_sui_json_response "json_data"
#   - json_data: JSON string to check (usually from _SUI_CMD_STDOUT)
# Returns: 0 on success, 1 on failure
# Note: Caller should check return value and decide whether to exit
check_sui_json_response() {
  local json_data="$1"
  
  # Check if output is valid JSON
  if ! echo "$json_data" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response" >&2
    echo "Output:" >&2
    echo "$json_data" >&2
    return 1
  fi
  
  # Check if JSON contains error field
  if echo "$json_data" | jq -e '.error' > /dev/null 2>&1; then
    echo "Error: JSON response contains error field" >&2
    echo "$json_data" | jq '.error' >&2
    return 1
  fi
  
  return 0
}
