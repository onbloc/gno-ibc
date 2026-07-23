#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
env_file=${ENV_FILE:-"$script_dir/.env"}

[[ -r $env_file ]] || {
  echo "missing environment file: $env_file" >&2
  exit 2
}
env_mode=$(stat -f '%Lp' "$env_file" 2>/dev/null ||
  stat -c '%a' "$env_file" 2>/dev/null) || {
  echo "cannot inspect environment file permissions" >&2
  exit 2
}
if [[ ! $env_mode =~ ^[0-7]{3,4}$ ]] || (((8#$env_mode & 077) != 0)); then
  echo "environment file must not be accessible by group or other users" >&2
  exit 2
fi

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

export E2E_SCRIPT_DIR=$script_dir
cd "$script_dir"
exec env GOWORK=off go run ./cmd/channel-e2e "$@"
