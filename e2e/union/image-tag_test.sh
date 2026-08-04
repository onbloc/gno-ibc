#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/repo"
mkdir -p \
  "$repo/e2e/union/gno" \
  "$repo/gno.land" \
  "$repo/third_party/gno-realms" \
  "$repo/third_party/gnolang-gno" \
  "$repo/third_party/gnoswap"
cp "$script_dir/image-tag.sh" "$repo/e2e/union/image-tag.sh"
for path in \
  .dockerignore .gno-version .gitmodules Makefile \
  e2e/union/Dockerfile e2e/union/config.jsonc.template \
  e2e/union/gno/entrypoint.sh e2e/union/union-deployer.nix \
  e2e/union/union-deployer-trusted-mpt.patch gno.land/example.gno; do
  mkdir -p "$repo/$(dirname "$path")"
  printf '%s\n' "$path" >"$repo/$path"
done

git -C "$repo" init -q
git -C "$repo" add .

gno_tag=$({ cd "$repo"; e2e/union/image-tag.sh gno; })
[[ $gno_tag =~ ^[0-9a-f]{40}$ ]]

printf 'changed\n' >>"$repo/gno.land/example.gno"
changed_gno_tag=$({ cd "$repo"; e2e/union/image-tag.sh gno; })
test "$gno_tag" != "$changed_gno_tag"

revision=82c70ec1ff84ec457e976ad94f38a5d5783b7836
voyager_tag=$({ cd "$repo"; UNION_VOYAGER_REVISION=$revision e2e/union/image-tag.sh voyager; })
deployer_tag=$({ cd "$repo"; UNION_VOYAGER_REVISION=$revision e2e/union/image-tag.sh union-deployer; })
test "$voyager_tag" != "$deployer_tag"
