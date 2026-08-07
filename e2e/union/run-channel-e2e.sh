#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
config_file=${E2E_CONFIG_FILE:-"$script_dir/runner.json"}

config_file=$(cd "$(dirname "$config_file")" && pwd -P)/$(basename "$config_file")

cd "$script_dir"
exec env GOWORK=off go run ./cmd/channel-e2e --config "$config_file" "$@"
