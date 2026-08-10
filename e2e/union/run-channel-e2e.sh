#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
config_file=${E2E_CONFIG_FILE:-"$script_dir/runner.json"}

case ${1:-} in
  list|plan) exec python3 "$script_dir/e2e.py" "$@" ;;
  *) exec python3 "$script_dir/e2e.py" "$@" --config "$config_file" ;;
esac
