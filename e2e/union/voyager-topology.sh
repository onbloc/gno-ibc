ibc_state() {
  voyager rpc ibc-state "$1" "$2" 2>/dev/null
}
find_connection() {
  local chain=$1 local_client=$2 remote_client=$3 id=1 result
  while result=$(ibc_state "$chain" "{\"connection\":{\"connection_id\":$id}}") &&
    [[ $(jq -r '.state != null' <<<"$result") == true ]]; do
    if jq -e --argjson local "$local_client" --argjson remote "$remote_client" \
      '.state.state == "open" and .state.client_id == $local and .state.counterparty_client_id == $remote' \
      <<<"$result" >/dev/null; then
      printf '%s\n' "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

find_channel() {
  local chain=$1 connection=$2 counterparty_port=$3 id=1 result
  while result=$(ibc_state "$chain" "{\"channel\":{\"channel_id\":$id}}") &&
    [[ $(jq -r '.state != null' <<<"$result") == true ]]; do
    if jq -e --argjson connection "$connection" --arg port "$counterparty_port" --arg version "$version" \
      '.state.state == "open" and .state.connection_id == $connection and
       (.state.counterparty_port_id | ascii_downcase) == ($port | ascii_downcase) and .state.version == $version' \
      <<<"$result" >/dev/null; then
      printf '%s\n' "$id"
      return
    fi
    ((id += 1))
  done
  return 1
}

wait_for() {
  local label=$1 finder=$2 deadline=$((SECONDS + 360)) value
  shift 2
  while ((SECONDS < deadline)); do
    if value=$($finder "$@"); then
      printf '%s\n' "$value"
      return
    fi
    sleep 2
  done
  echo "$label did not open within 360 seconds" >&2
  return 1
}
