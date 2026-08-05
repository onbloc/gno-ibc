#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/go" <<'EOF'
#!/usr/bin/env bash
test "$GOWORK" = off
printf '%s\n' "$*"
EOF
chmod +x "$tmp/go"

config_file="$tmp/runner.json"
printf '{}\n' >"$config_file"
chmod 600 "$config_file"
output=$(PATH="$tmp:$PATH" E2E_CONFIG_FILE="$config_file" \
  "$script_dir/run-channel-e2e.sh" --apply)
resolved_config_file=$(cd "$(dirname "$config_file")" && pwd -P)/$(basename "$config_file")
test "$output" = "run ./cmd/channel-e2e --config $resolved_config_file --apply"

chmod 640 "$config_file"
if PATH="$tmp:$PATH" E2E_CONFIG_FILE="$config_file" \
  "$script_dir/run-channel-e2e.sh" --apply 2>"$tmp/error"; then
  echo "group-readable runner config was accepted" >&2
  exit 1
fi
grep -qx 'runner config must not be accessible by group or other users' \
  "$tmp/error"
