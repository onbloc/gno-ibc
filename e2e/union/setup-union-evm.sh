#!/bin/sh
set -eu

UNION_VOYAGER_DIR=${UNION_VOYAGER_DIR:-/Users/notjoon/union-voyager}
UNION_CONTAINER=${UNION_CONTAINER:-full-dev-setup-union-0-1}
UNION_CORE_CONTRACT=${UNION_CORE_CONTRACT:-union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t}
UNION_MANAGER_CONTRACT=${UNION_MANAGER_CONTRACT:-union1g8eayx25kmzmywzwq4uw44ftfpqxfz6qplnyutwqdzn92reavtmqltyh3e}
UNION_CHAIN_ID=${UNION_CHAIN_ID:-union-devnet-1}
UNION_SIGNER_KEY=${UNION_SIGNER_KEY:-alice}
UNION_SIGNER_HOME=${UNION_SIGNER_HOME:-home}
TRUSTED_MPT_WASM=${TRUSTED_MPT_WASM:-"$UNION_VOYAGER_DIR/target/wasm32-unknown-unknown/wasm-release/trusted_mpt_light_client.wasm"}
CLIENT_TYPE=trusted/evm/mpt
SALT=lightclients/trusted/evm/mpt

UNION_VOYAGER_DIR="$UNION_VOYAGER_DIR" TRUSTED_MPT_WASM="$TRUSTED_MPT_WASM" "$(dirname "$0")/verify-pins.sh"

uniond() {
	docker exec "$UNION_CONTAINER" uniond "$@"
}

query_registered() {
	uniond query wasm contract-state smart "$UNION_CORE_CONTRACT" \
		'{"get_registered_client_type":{"client_type":"trusted/evm/mpt"}}' \
		--node tcp://localhost:26657 -o json 2>/dev/null
}

wait_tx() {
	txhash=$1
	i=0
	while [ "$i" -lt 30 ]; do
		if result=$(uniond query tx "$txhash" --node tcp://localhost:26657 -o json 2>/dev/null); then
			code=$(printf '%s' "$result" | jq -r '.code // 0')
			if [ "$code" != 0 ]; then
				printf 'transaction %s failed:\n%s\n' "$txhash" "$result" >&2
				exit 1
			fi
			printf '%s' "$result"
			return
		fi
		i=$((i + 1))
		sleep 1
	done
	printf 'transaction %s was not committed within 30 seconds\n' "$txhash" >&2
	exit 1
}

broadcast() {
	out=$(uniond tx "$@" \
		--from "$UNION_SIGNER_KEY" \
		--keyring-backend test \
		--home "$UNION_SIGNER_HOME" \
		--chain-id "$UNION_CHAIN_ID" \
		--node tcp://localhost:26657 \
		--gas auto \
		--gas-adjustment 1.5 \
		--gas-prices 1au \
		--yes \
		--broadcast-mode sync \
		-o json)
	txhash=$(printf '%s' "$out" | jq -r '.txhash // empty')
	if [ -z "$txhash" ]; then
		printf 'broadcast did not return a transaction hash:\n%s\n' "$out" >&2
		exit 1
	fi
	wait_tx "$txhash"
}

if registered=$(query_registered); then
	address=$(printf '%s' "$registered" | jq -r '.data // empty')
	if [ -n "$address" ]; then
		contract=$(uniond query wasm contract "$address" --node tcp://localhost:26657 -o json)
		code_id=$(printf '%s' "$contract" | jq -r '.contract_info.code_id // empty')
		if [ -z "$code_id" ]; then
			printf 'registered %s address %s has no code id\n' "$CLIENT_TYPE" "$address" >&2
			exit 1
		fi
		uniond query wasm code-info "$code_id" --node tcp://localhost:26657 -o json >/dev/null
		printf '%s is already registered at %s (code id %s); no changes made\n' "$CLIENT_TYPE" "$address" "$code_id"
		exit 0
	fi
fi

if [ ! -f "$TRUSTED_MPT_WASM" ]; then
	printf 'trusted MPT artifact is missing: %s\n' "$TRUSTED_MPT_WASM" >&2
	printf 'build it from the pinned checkout with:\n' >&2
	printf '  cd %s && RUSTFLAGS=%s cargo +nightly-2025-12-05 build -Z build-std=std,panic_abort --profile wasm-release --target wasm32-unknown-unknown --no-default-features --lib -p trusted-mpt-light-client\n' \
		"$UNION_VOYAGER_DIR" "'-C link-arg=-s -C target-cpu=mvp -C passes=adce,loop-deletion -Zlocation-detail=none'" >&2
	exit 1
fi

uniond query wasm code-info 1 --node tcp://localhost:26657 -o json >/dev/null || {
	printf 'bytecode-base code id 1 is not present; run the pinned Union CosmWasm deployment first\n' >&2
	exit 1
}

container_wasm=/tmp/trusted_mpt_light_client.wasm
docker cp "$TRUSTED_MPT_WASM" "$UNION_CONTAINER:$container_wasm"
store=$(broadcast wasm store "$container_wasm")
code_id=$(printf '%s' "$store" | jq -r '[.events[]? | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value][0] // empty')
if [ -z "$code_id" ]; then
	printf 'could not find stored code id:\n%s\n' "$store" >&2
	exit 1
fi

signer=$(uniond keys show "$UNION_SIGNER_KEY" -a --keyring-backend test --home "$UNION_SIGNER_HOME")
instantiate=$(broadcast wasm instantiate2 1 '{}' "$SALT" \
	--ascii \
	--admin "$signer" \
	--label "$SALT")
address=$(printf '%s' "$instantiate" | jq -r '[.events[]? | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value][0] // empty')
if [ -z "$address" ]; then
	printf 'could not find deterministic contract address:\n%s\n' "$instantiate" >&2
	exit 1
fi

init=$(jq -cn \
	--arg core "$UNION_CORE_CONTRACT" \
	--arg manager "$UNION_MANAGER_CONTRACT" \
	'{init:{ibc_host:$core,access_managed_init_msg:{initial_authority:$manager}}}')
broadcast wasm migrate "$address" "$code_id" "$init" >/dev/null
broadcast wasm set-contract-admin "$address" "$address" >/dev/null
register=$(jq -cn \
	--arg client_type "$CLIENT_TYPE" \
	--arg client_address "$address" \
	'{register_client:{client_type:$client_type,client_address:$client_address}}')
broadcast wasm execute "$UNION_CORE_CONTRACT" "$register" >/dev/null

registered=$(query_registered)
got=$(printf '%s' "$registered" | jq -r '.data // empty')
if [ "$got" != "$address" ]; then
	printf 'registration verification failed: got %s, want %s\n' "$got" "$address" >&2
	exit 1
fi
printf 'registered %s at %s (code id %s)\n' "$CLIENT_TYPE" "$address" "$code_id"
