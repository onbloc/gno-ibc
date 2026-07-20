#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
fixture_env=${FIXTURE_ENV_FILE:-"$script_dir/forward-fixture.env"}
evm_rpc=${EVM_RPC:-http://localhost:8545}
evm_zkgm=${EVM_ZKGM:?set EVM_ZKGM}
evm_erc20_impl=${EVM_ERC20_IMPL:?set EVM_ERC20_IMPL}
evm_manager=${EVM_MANAGER:?set EVM_MANAGER}
evm_recipient=${EVM_RECIPIENT:?set EVM_RECIPIENT}
gno_sender=${GNO_SENDER_ADDR:?set GNO_SENDER_ADDR}
union_gno_channel=${UNION_PACKET_CHANNEL_ID:?set UNION_PACKET_CHANNEL_ID}
union_evm_channel=${UNION_EVM_CHANNEL_ID:?set UNION_EVM_CHANNEL_ID}
evm_union_channel=${EVM_UNION_CHANNEL_ID:?set EVM_UNION_CHANNEL_ID}
base_token=${GNO_PACKET_BASE_TOKEN:-ugnot}
base_amount=${GNO_PACKET_BASE_AMOUNT:-1}
run_tag=${GITHUB_RUN_ID:-$(date +%s)}-${GITHUB_RUN_ATTEMPT:-1}
name="Gno CI ${run_tag}"
symbol="GCI${run_tag//[^0-9]/}"
decimals=6

[[ $base_amount =~ ^[1-9][0-9]*$ ]] || { echo "invalid GNO_PACKET_BASE_AMOUNT=$base_amount" >&2; exit 2; }

ascii_hex() {
  printf '0x'
  printf %s "$1" | od -An -tx1 | tr -d ' \n'
  printf '\n'
}

initializer=$(cast calldata 'initialize(address,address,string,string,uint8)' \
  "$evm_manager" "$evm_zkgm" "$name" "$symbol" "$decimals")
metadata=$(cast abi-encode 'f(bytes,bytes)' "$evm_erc20_impl" "$initializer")
base_token_hex=$(ascii_hex "$base_token")
sender_hex=$(ascii_hex "$gno_sender")
path=$((union_gno_channel | (union_evm_channel << 32)))

prediction=$(cast call "$evm_zkgm" \
  'predictWrappedTokenV2(uint256,uint32,bytes,(bytes,bytes))(address,bytes32)' \
  "$path" "$evm_union_channel" "$base_token_hex" \
  "($evm_erc20_impl,$initializer)" --rpc-url "$evm_rpc")
wrapped_token=${prediction%%[[:space:]]*}
[[ $wrapped_token =~ ^0x[0-9a-fA-F]{40}$ ]] || { echo "invalid wrapped-token prediction" >&2; exit 1; }

order=$(cast abi-encode 'f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)' \
  "$sender_hex" "$evm_recipient" "$base_token_hex" "$base_amount" \
  "$wrapped_token" "$base_amount" 0 "$metadata")
timeout=$((( $(date +%s) + 3600 ) * 1000000000))
forward=$(cast abi-encode 'f(uint256,uint64,uint64,(uint8,uint8,bytes))' \
  "$path" 0 "$timeout" "(2,3,$order)")
salt=0x$(openssl rand -hex 32)

umask 077
{
  printf 'GNO_EVM_FORWARD_OPERAND_HEX=%s\n' "$forward"
  printf 'GNO_PACKET_SALT_HEX=%s\n' "$salt"
  printf 'GNO_PACKET_SEND_COINS=%s%s\n' "$base_amount" "$base_token"
  printf 'EVM_WRAPPED_TOKEN=%s\n' "$wrapped_token"
} >"$fixture_env"
echo "wrote fresh Forward fixture to $fixture_env"
