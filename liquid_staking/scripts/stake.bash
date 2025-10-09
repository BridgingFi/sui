#!/usr/bin/env bash

ENVIRONMENT=$1
SCRIPT_PATH=$(dirname "$0")

source "$SCRIPT_PATH/../.env-$ENVIRONMENT"

echo "Contract setup..."

GAS_BUDGET=${GAS_BUDGET:=300000000}
echo "Gas budget: $GAS_BUDGET"
echo "Package: $PACKAGE"
echo "Validators: $VALIDATOR_SET_ADDRS"
echo "Priorities: $VALIDATOR_SET_PRIORS"
echo "Stake pool: $STAKE_POOL"
echo "Coin metadata: $2"

# [0x..,0x..,0x...] is validators presented on network
# [1,2,3] their priority
sui client call --function stake_entry --module stake_pool --package "$PACKAGE" --args "$STAKE_POOL" "$CERT_METADATA" "0x5" "0xb21856f862464ac6af814515a1d1742bf5b140a82e4f220bac7b689a5ba50894" --gas-budget "$GAS_BUDGET"

exit 0