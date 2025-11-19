#!/bin/bash

# Per-environment and per-branch build commands
# Reference: https://vercel.com/guides/per-environment-and-per-branch-build-commands

if [[ $VERCEL_ENV == "production"  ]] ; then 
  pnpm run build
elif [[ $VERCEL_GIT_COMMIT_REF == "testnet" ]]; then
  pnpm run build:testnet
else
  pnpm run build
fi