#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
config_file=${E2E_CONFIG_FILE:-"$script_dir/runner.json"}

[[ -r $config_file ]] || {
  echo "missing runner config: $config_file" >&2
  exit 2
}
config_mode=$(stat -c '%a' "$config_file" 2>/dev/null ||
  stat -f '%Lp' "$config_file" 2>/dev/null) || {
  echo "cannot inspect runner config permissions" >&2
  exit 2
}
if [[ ! $config_mode =~ ^[0-7]{3,4}$ ]] || (((8#$config_mode & 077) != 0)); then
  echo "runner config must not be accessible by group or other users" >&2
  exit 2
fi
config_file=$(cd "$(dirname "$config_file")" && pwd -P)/$(basename "$config_file")

cd "$script_dir"
exec env GOWORK=off go run ./cmd/channel-e2e --config "$config_file" "$@"
