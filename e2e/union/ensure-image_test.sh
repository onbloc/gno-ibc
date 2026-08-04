#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOCKER_LOG"
case "$*" in
  "buildx imagetools inspect "*":remote") exit 0 ;;
  "buildx imagetools inspect "*) exit 1 ;;
  "image inspect "*) exit 1 ;;
esac
EOF
chmod +x "$tmp/docker"

export PATH="$tmp:$PATH"
export DOCKER_LOG="$tmp/docker.log"
export E2E_REGISTRY=registry.example

E2E_IMAGE_TAG=remote "$script_dir/ensure-image.sh" gno >/dev/null
grep -q '^pull registry.example/onbloc/gno-ibc-e2e-gno:remote$' "$DOCKER_LOG"

: >"$DOCKER_LOG"
E2E_IMAGE_TAG=missing "$script_dir/ensure-image.sh" gno >/dev/null
grep -q '^buildx build --target gno --progress plain --load --tag registry.example/onbloc/gno-ibc-e2e-gno:missing ' "$DOCKER_LOG"
