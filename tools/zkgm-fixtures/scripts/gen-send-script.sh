#!/usr/bin/env bash
# Render zkgm.Send maketx-run scripts from scenarios.json.
#
# By default writes one .gno per selected scenario into ./out/.
# With --exec, invokes `gnokey maketx run` against the rendered script using
# the env-configured chain/remote/signer.
#
# Required env (only with --exec):
#   GNOKEY_REMOTE     e.g. tcp://127.0.0.1:26657
#   GNOKEY_CHAINID    e.g. dev
#   GNOKEY_KEYNAME    e.g. test1  (the address/keyname `gnokey` resolves)
# Optional:
#   GNOKEY_GAS_FEE    default 1000000ugnot
#   GNOKEY_GAS_WANTED default 90000000
#   GNOKEY_BIN        default gnokey

set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage: $0 [--all | <scenario-name>] [--exec] [--out <dir>] [--scenarios <path>]

  --all                 Render every scenario.
  <scenario-name>       Render only the named scenario (e.g. recv_call_eureka_true).
  --exec                After rendering, invoke 'gnokey maketx run' for each script.
                        Requires GNOKEY_REMOTE, GNOKEY_CHAINID, GNOKEY_KEYNAME.
  --out <dir>           Output directory (default: ./out next to this script).
  --scenarios <path>    Override scenarios.json path (default: derived from repo).

  -h, --help            Show this message.

Examples:
  $0 --all
  $0 recv_call_eureka_true
  GNOKEY_REMOTE=tcp://127.0.0.1:26657 GNOKEY_CHAINID=dev GNOKEY_KEYNAME=alice \\
      $0 recv_token_order_v2_escrow_protocol_fill --exec
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DEFAULT_SCENARIOS="$REPO_ROOT/gno.land/p/core/ibc/zkgm/testdata/scenarios.json"
TEMPLATE="$SCRIPT_DIR/send_template.gno"
OUT_DIR="$SCRIPT_DIR/out"
SCENARIOS_PATH="$DEFAULT_SCENARIOS"
SELECT="" # empty = require --all or a name
DO_EXEC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --all) SELECT="__all__"; shift ;;
    --exec) DO_EXEC=1; shift ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --scenarios) SCENARIOS_PATH="$2"; shift 2 ;;
    --) shift; break ;;
    -*) echo "unknown flag: $1" >&2; usage; exit 2 ;;
    *)
      if [[ -n "$SELECT" && "$SELECT" != "__all__" ]]; then
        echo "only one scenario name allowed (got '$SELECT' and '$1')" >&2
        exit 2
      fi
      [[ "$SELECT" == "__all__" ]] && { echo "--all and a scenario name are mutually exclusive" >&2; exit 2; }
      SELECT="$1"; shift ;;
  esac
done

if [[ -z "$SELECT" ]]; then
  usage; exit 2
fi
if [[ ! -f "$SCENARIOS_PATH" ]]; then
  echo "scenarios file not found: $SCENARIOS_PATH" >&2
  exit 1
fi
if [[ ! -f "$TEMPLATE" ]]; then
  echo "template not found: $TEMPLATE" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

mkdir -p "$OUT_DIR"

# Strip '0x' prefix from hex string. Empty input -> empty output.
strip0x() { local s="$1"; if [[ "$s" == 0x* || "$s" == 0X* ]]; then printf '%s' "${s:2}"; else printf '%s' "$s"; fi; }

# Pick scenario names from JSON. `while read` keeps this portable to
# bash 3.2 (macOS system bash, no mapfile/readarray).
NAMES=()
if [[ "$SELECT" == "__all__" ]]; then
  while IFS= read -r line; do
    NAMES+=("$line")
  done < <(jq -r '.[].name' "$SCENARIOS_PATH")
else
  if ! jq -e --arg n "$SELECT" 'any(.[]; .name == $n)' "$SCENARIOS_PATH" >/dev/null; then
    echo "scenario not found: $SELECT" >&2
    echo "available:" >&2
    jq -r '.[].name | "  - " + .' "$SCENARIOS_PATH" >&2
    exit 1
  fi
  NAMES=("$SELECT")
fi

if [[ $DO_EXEC -eq 1 ]]; then
  : "${GNOKEY_REMOTE:?GNOKEY_REMOTE required with --exec}"
  : "${GNOKEY_CHAINID:?GNOKEY_CHAINID required with --exec}"
  : "${GNOKEY_KEYNAME:?GNOKEY_KEYNAME required with --exec}"
  GNOKEY_BIN="${GNOKEY_BIN:-gnokey}"
  GNOKEY_GAS_FEE="${GNOKEY_GAS_FEE:-1000000ugnot}"
  GNOKEY_GAS_WANTED="${GNOKEY_GAS_WANTED:-90000000}"
  command -v "$GNOKEY_BIN" >/dev/null 2>&1 || { echo "gnokey binary not on PATH: $GNOKEY_BIN" >&2; exit 1; }
fi

render_one() {
  local name="$1"
  # Pull every field in one jq pass — emitting tsv so bash can split with
  # IFS. Avoids one jq invocation per field × per scenario.
  local tsv
  tsv="$(jq -r --arg n "$name" '
    .[] | select(.name == $n) | [
      .instruction_type,
      .source_channel,
      .packet.salt,
      .packet.instruction.version,
      .packet.instruction.opcode,
      .packet.instruction.operand,
      .tx_timeout_timestamp
    ] | @tsv
  ' "$SCENARIOS_PATH")"

  local instr_type src_channel salt_hex_full version opcode operand_hex_full tx_timeout
  IFS=$'\t' read -r instr_type src_channel salt_hex_full version opcode operand_hex_full tx_timeout <<<"$tsv"
  local salt_hex operand_hex
  salt_hex="$(strip0x "$salt_hex_full")"
  operand_hex="$(strip0x "$operand_hex_full")"

  local out_file="$OUT_DIR/${name}.gno"
  sed \
    -e "s|@@SCENARIO_NAME@@|${name}|g" \
    -e "s|@@INSTRUCTION_TYPE@@|${instr_type}|g" \
    -e "s|@@SOURCE_CHANNEL@@|${src_channel}|g" \
    -e "s|@@SALT_HEX@@|${salt_hex}|g" \
    -e "s|@@VERSION@@|${version}|g" \
    -e "s|@@OPCODE@@|${opcode}|g" \
    -e "s|@@OPERAND_HEX@@|${operand_hex}|g" \
    -e "s|@@TX_TIMEOUT_TIMESTAMP@@|${tx_timeout}|g" \
    "$TEMPLATE" > "$out_file"
  echo "rendered: $out_file"
  if [[ $DO_EXEC -eq 1 ]]; then
    echo ">> gnokey maketx run $out_file"
    # `-insecure-password-stdin` lets dev/CI flows feed an empty (or scripted)
    # password on stdin instead of opening /dev/tty. Set GNOKEY_PASSWORD to
    # override; default is empty, which matches the keyring on `gnodev local`.
    printf '%s\n' "${GNOKEY_PASSWORD-}" | "$GNOKEY_BIN" maketx run \
      -gas-fee "$GNOKEY_GAS_FEE" \
      -gas-wanted "$GNOKEY_GAS_WANTED" \
      -broadcast \
      -insecure-password-stdin \
      -chainid "$GNOKEY_CHAINID" \
      -remote "$GNOKEY_REMOTE" \
      "$GNOKEY_KEYNAME" "$out_file"
  fi
}

for n in "${NAMES[@]}"; do
  render_one "$n"
done
