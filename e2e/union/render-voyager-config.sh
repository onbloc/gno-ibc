#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
template=${VOYAGER_CONFIG_TEMPLATE:-"$script_dir/voyager-config.gno-union.jsonc"}
output=${VOYAGER_CONFIG_OUTPUT:?set VOYAGER_CONFIG_OUTPUT}
command -v jq >/dev/null || { echo "missing required command: jq" >&2; exit 2; }

[[ ${EVM_CHAIN_ID:-} =~ ^[1-9][0-9]*$ ]] || {
  echo "EVM_CHAIN_ID must be a positive decimal integer" >&2
  exit 2
}
for name in EVM_IBC_HANDLER EVM_MULTICALL; do
  value=${!name:-}
  [[ $value =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "$name must be a 20-byte hex address" >&2; exit 2; }
done
for name in TRUSTED_MPT_PRIVATE_KEY UNION_PRIVATE_KEY EVM_PRIVATE_KEY GNO_PRIVATE_KEY; do
  value=${!name:-}
  [[ $value =~ ^0x[0-9a-fA-F]{64}$ ]] || { echo "$name must be a 0x-prefixed 32-byte key" >&2; exit 2; }
done

umask 077
export UNION_RPC_INTERNAL=${UNION_RPC_INTERNAL:-http://host.docker.internal:26657}
export EVM_RPC_INTERNAL=${EVM_RPC_INTERNAL:-http://host.docker.internal:8545}
jq '
  walk(if type == "string" then
    if . == "__UNION_RPC_INTERNAL__" then $ENV.UNION_RPC_INTERNAL
    elif . == "__EVM_RPC_INTERNAL__" then $ENV.EVM_RPC_INTERNAL
    elif . == "__EVM_CHAIN_ID__" then $ENV.EVM_CHAIN_ID
    elif . == "__EVM_IBC_HANDLER__" then $ENV.EVM_IBC_HANDLER
    elif . == "__EVM_MULTICALL__" then $ENV.EVM_MULTICALL
    elif . == "__TRUSTED_MPT_PRIVATE_KEY__" then $ENV.TRUSTED_MPT_PRIVATE_KEY
    elif . == "__UNION_PRIVATE_KEY__" then $ENV.UNION_PRIVATE_KEY
    elif . == "__EVM_PRIVATE_KEY__" then $ENV.EVM_PRIVATE_KEY
    elif . == "__GNO_PRIVATE_KEY__" then $ENV.GNO_PRIVATE_KEY
    else . end
  else . end)
' "$template" >"$output"
chmod 600 "$output"

if grep -En '__[A-Z0-9_]+__' "$output" >/dev/null; then
  echo "unrendered Voyager config placeholder" >&2
  exit 1
fi
echo "rendered Voyager config"
