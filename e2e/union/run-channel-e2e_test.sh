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

env_file="$tmp/.env"
: >"$env_file"
chmod 600 "$env_file"
output=$(PATH="$tmp:$PATH" ENV_FILE="$env_file" \
  "$script_dir/run-channel-e2e.sh" --apply)
test "$output" = "run ./cmd/channel-e2e --apply"

chmod 640 "$env_file"
if PATH="$tmp:$PATH" ENV_FILE="$env_file" \
  "$script_dir/run-channel-e2e.sh" --apply 2>"$tmp/error"; then
  echo "group-readable environment file was accepted" >&2
  exit 1
fi
grep -qx 'environment file must not be accessible by group or other users' \
  "$tmp/error"
