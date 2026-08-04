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

cat >"$tmp/make" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MAKE_LOG"
EOF
chmod +x "$tmp/make"

export PATH="$tmp:$PATH"
export DOCKER_LOG="$tmp/docker.log"
export MAKE_LOG="$tmp/make.log"
export E2E_REGISTRY=registry.example

E2E_IMAGE_TAG=remote "$script_dir/ensure-image.sh" gno >/dev/null
grep -q '^pull registry.example/onbloc/gno-ibc-e2e-gno:remote$' "$DOCKER_LOG"
test ! -s "$MAKE_LOG"

: >"$DOCKER_LOG"
E2E_IMAGE_TAG=remote \
UNION_VOYAGER_REVISION=82c70ec1ff84ec457e976ad94f38a5d5783b7836 \
  "$script_dir/ensure-image.sh" union-deployer >/dev/null
grep -q '^pull registry.example/onbloc/gno-ibc-e2e-union-deployer:remote$' "$DOCKER_LOG"

: >"$DOCKER_LOG"
E2E_IMAGE_TAG=missing "$script_dir/ensure-image.sh" gno >/dev/null
grep -q "^-C $(cd "$script_dir/../.." && pwd -P) vendor$" "$MAKE_LOG"
grep -q '^buildx build --target gno --progress plain --load --tag registry.example/onbloc/gno-ibc-e2e-gno:missing ' "$DOCKER_LOG"
