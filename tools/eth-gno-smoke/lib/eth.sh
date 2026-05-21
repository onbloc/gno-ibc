#!/usr/bin/env bash
# eth.sh — local anvil lifecycle for ETH-side smoke scenarios.
# Requires lib/env.sh (init_smoke_env, ANVIL_* config) to be sourced first.

start_anvil() {
  init_smoke_env

  if cast block-number --rpc-url "$ANVIL_RPC_URL" >/dev/null 2>&1; then
    echo "ERROR: $ANVIL_RPC_URL already responds before smoke anvil startup"
    echo "Stop the existing anvil process or choose an isolated ANVIL_PORT/ANVIL_RPC_URL."
    exit 1
  fi

  echo ">> starting anvil on $ANVIL_HOST:$ANVIL_PORT"
  anvil --host "$ANVIL_HOST" --port "$ANVIL_PORT" >"$WORKDIR/anvil.log" 2>&1 &
  ANVIL_PID=$!
  sleep 0.2
  if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
    echo "anvil exited unexpectedly"
    cat "$WORKDIR/anvil.log"
    exit 1
  fi

  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if cast block-number --rpc-url "$ANVIL_RPC_URL" >/dev/null 2>&1; then
      echo ">> anvil ready"
      return
    fi
    if ! kill -0 "$ANVIL_PID" 2>/dev/null; then
      echo "anvil exited unexpectedly"
      cat "$WORKDIR/anvil.log"
      exit 1
    fi
    sleep 1
  done

  echo "anvil not ready within 30s"
  cat "$WORKDIR/anvil.log"
  exit 1
}
