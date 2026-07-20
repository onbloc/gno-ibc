#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
template=${VOYAGER_CONFIG_TEMPLATE:-"$script_dir/voyager-config.gno-union.jsonc"}
output=${VOYAGER_CONFIG_OUTPUT:?set VOYAGER_CONFIG_OUTPUT}

for name in TRUSTED_MPT_PRIVATE_KEY UNION_PRIVATE_KEY EVM_PRIVATE_KEY GNO_PRIVATE_KEY; do
  value=${!name:-}
  [[ $value =~ ^0x[0-9a-fA-F]{64}$ ]] || { echo "$name must be a 0x-prefixed 32-byte key" >&2; exit 2; }
done

umask 077
sed \
  -e "s/__TRUSTED_MPT_PRIVATE_KEY__/$TRUSTED_MPT_PRIVATE_KEY/g" \
  -e "s/__UNION_PRIVATE_KEY__/$UNION_PRIVATE_KEY/g" \
  -e "s/__EVM_PRIVATE_KEY__/$EVM_PRIVATE_KEY/g" \
  -e "s/__GNO_PRIVATE_KEY__/$GNO_PRIVATE_KEY/g" \
  "$template" >"$output"

if grep -En '__[A-Z0-9_]+__' "$output" >/dev/null; then
  echo "unrendered Voyager config placeholder" >&2
  exit 1
fi
echo "rendered Voyager config"
