#!/usr/bin/env bash
set -euo pipefail

SCENARIO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETH_GNO_SMOKE_DIR="$(cd "$SCENARIO_DIR/../.." && pwd)"
source "$ETH_GNO_SMOKE_DIR/lib/env.sh"

SEPOLIA_RPC_URL="${SEPOLIA_RPC_URL:-}"
if [[ -z "$SEPOLIA_RPC_URL" ]]; then
  echo "ERROR: set SEPOLIA_RPC_URL to refresh Sepolia ugnot fixtures"
  exit 1
fi

OUT_DIR="$SCENARIO_DIR"

rpc() {
  local method="$1"
  local params="$2"
  jq -n \
    --arg method "$method" \
    --argjson params "$params" \
    '{jsonrpc: "2.0", id: 1, method: $method, params: $params}' \
    | curl -sf -H "content-type: application/json" --data @- "$SEPOLIA_RPC_URL"
}

require_command curl
require_command jq

TOKEN="0x4271eb8f0243f1e1f303912841fdce55c06cf223"
TRANSFER_TOPIC="0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
MINT_TX_1="0xa43e972bc1f20ddb548805660235ef436b8a7228354ee5558c4b24656d9ff1b6"
MINT_TX_2="0x586296ab07193c481245eec14e9c6488847cc43c8483d7decb33e0c1a61082be"
BURN_TX="0xfbd180c2706b966b669b5c001e4f71b3f413914718f5f2c31f11de69086973d1"

echo ">> fetching Sepolia ugnot Transfer logs"
rpc eth_getLogs "[{\"address\":\"$TOKEN\",\"topics\":[\"$TRANSFER_TOPIC\"],\"fromBlock\":\"0xa605e4\",\"toBlock\":\"0xa607f4\"}]" >"$OUT_DIR/ugnot-transfer-logs.tmp.json"

echo ">> fetching Sepolia ugnot burn receipt"
rpc eth_getTransactionReceipt "[\"$BURN_TX\"]" | jq -S . >"$OUT_DIR/ugnot-burn-receipt.json"

echo ">> fetching Sepolia ugnot burn transaction"
rpc eth_getTransactionByHash "[\"$BURN_TX\"]" | jq -S . >"$OUT_DIR/ugnot-burn-tx.json"

jq -n -S \
  --arg token "$TOKEN" \
  --arg topic "$TRANSFER_TOPIC" \
  --arg mint_tx_1 "$MINT_TX_1" \
  --arg mint_tx_2 "$MINT_TX_2" \
  --arg burn_tx "$BURN_TX" \
  --slurpfile transferLogs "$OUT_DIR/ugnot-transfer-logs.tmp.json" \
  '
  def topic_addr($topic):
    "0x" + ($topic | sub("^0x"; "") | .[24:]);
  def hex_digit:
    if . >= 48 and . <= 57 then . - 48
    elif . >= 65 and . <= 70 then . - 55
    elif . >= 97 and . <= 102 then . - 87
    else error("invalid hex digit")
    end;
  def hex_to_number:
    reduce explode[] as $c (0; . * 16 + ($c | hex_digit));
  def amount_raw($data):
    ($data | sub("^0x"; "") | ltrimstr("0")) as $trimmed
    | if $trimmed == "" then "0" else $trimmed end
    | (hex_to_number | tostring);
  def amount_decimal($raw):
    ($raw | tonumber) as $n
    | "\(($n / 1000000) | floor).\(($n % 1000000) | tostring | (6 - length) as $pad | ("0" * $pad) + .)";
  def action($tx):
    if ($tx | ascii_downcase) == $mint_tx_1 then "mint"
    elif ($tx | ascii_downcase) == $mint_tx_2 then "mint"
    elif ($tx | ascii_downcase) == $burn_tx then "burn"
    else error("unexpected transfer tx " + $tx)
    end;
  def transfer($log):
    (amount_raw($log.data)) as $raw
    | {
        transaction_hash: $log.transactionHash,
        block_number: $log.blockNumber,
        action: action($log.transactionHash),
        address: $log.address,
        topics: $log.topics,
        data: $log.data,
        from: topic_addr($log.topics[1]),
        to: topic_addr($log.topics[2]),
        amount_raw: $raw,
        amount_decimal: amount_decimal($raw)
      };
  {
    network: "sepolia",
    source: {
      rpc_methods: ["eth_getLogs", "eth_getTransactionReceipt", "eth_getTransactionByHash"],
      rpc_env_var: "SEPOLIA_RPC_URL"
    },
    token: {
      address: $token,
      symbol: "ugnot",
      decimals: 6,
      proxy_implementation: "0xAf739F34ddF951cBC24fdbBa4f76213688E13627"
    },
    transfer_event_signature: $topic,
    logs: ($transferLogs[0].result
      | map(select((.transactionHash | ascii_downcase) == $mint_tx_1 or (.transactionHash | ascii_downcase) == $mint_tx_2 or (.transactionHash | ascii_downcase) == $burn_tx))
      | sort_by(.blockNumber, .logIndex)
      | map(transfer(.)))
  }' >"$OUT_DIR/ugnot-token-transfers.json"

rm -f "$OUT_DIR/ugnot-transfer-logs.tmp.json"

minted="$(jq -r '[.logs[] | select(.action == "mint") | .amount_raw | tonumber] | add' "$OUT_DIR/ugnot-token-transfers.json")"
burned="$(jq -r '[.logs[] | select(.action == "burn") | .amount_raw | tonumber] | add' "$OUT_DIR/ugnot-token-transfers.json")"
net=$((minted - burned))
echo "PASS: wrote Sepolia ugnot fixtures to $OUT_DIR"
echo "      minted_raw=$minted burned_raw=$burned net_raw=$net"
