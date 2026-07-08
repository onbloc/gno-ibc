#!/bin/bash
set -eu

GNO_CHAIN_ID="${GNO_CHAIN_ID:-dev}"
UNION_CHAIN_ID="${UNION_CHAIN_ID:-union-devnet-1}"
UNION_GAS_PRICE="${UNION_GAS_PRICE:-1muno}"

/bin/with_keyring bash -c "
  ibc-v2-ts-relayer add-mnemonic -c $GNO_CHAIN_ID --mnemonic \"$RELAYER_MNEMONIC\"
  ibc-v2-ts-relayer add-mnemonic -c $UNION_CHAIN_ID --mnemonic \"$RELAYER_MNEMONIC\"

  ibc-v2-ts-relayer add-gas-price -c $GNO_CHAIN_ID 0.025ugnot --gas-adjustment 2.0
  ibc-v2-ts-relayer add-gas-price -c $UNION_CHAIN_ID $UNION_GAS_PRICE --gas-adjustment 2.0

  ibc-v2-ts-relayer add-path \
    -s $GNO_CHAIN_ID -d $UNION_CHAIN_ID \
    --surl ${GNO_RPC_INTERNAL:-http://gno:26657} \
    --durl ${UNION_RPC_INTERNAL:-http://host.docker.internal:26657} \
    --squery ${GNO_INDEXER_INTERNAL:-http://tx-indexer:8546/graphql/query} \
    --st gno --dt cosmos \
    --ibcv 2

  exec \"\$@\"
" -- "$@"
