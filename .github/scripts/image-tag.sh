#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/../.." && pwd -P)
component=${1:-}
system=${E2E_IMAGE_SYSTEM:-x86_64-linux}

case "$component" in
  gno)
    inputs=(
      .dockerignore
      .gno-version
      .gitmodules
      Makefile
      e2e/images/Dockerfile
      e2e/gno/entrypoint.sh
      e2e/gno/setup.sh
      gno.land
      third_party/gno-realms
      third_party/gnolang-gno
      third_party/gnoswap
    )
    ;;
  voyager)
    inputs=(
      .dockerignore
      e2e/images/Dockerfile
      e2e/config/config.jsonc.template
    )
    ;;
  union-deployer)
    inputs=(
      e2e/images/union-deployer/default.nix
      e2e/images/union-deployer/trusted-mpt.patch
    )
    ;;
  *)
    echo "usage: $0 gno|voyager|union-deployer" >&2
    exit 2
    ;;
esac

revision=
if [[ $component != gno ]]; then
  revision=${UNION_VOYAGER_REVISION:?set UNION_VOYAGER_REVISION}
fi

{
  printf 'gno-ibc-e2e-image-v1\0%s\0%s\0%s\0' \
    "$component" "$system" "$revision"
  {
    git -C "$repo_root" ls-files -z -- "${inputs[@]}"
    git -C "$repo_root" ls-files --others --exclude-standard -z -- "${inputs[@]}"
  } | sort -zu | while IFS= read -r -d '' path; do
    record=$(git -C "$repo_root" ls-files -s -- "$path")
    if [[ ${record%% *} == 160000 ]]; then
      digest=${record#* }
      digest=${digest%% *}
    elif [[ -f $repo_root/$path ]]; then
      digest=$(git hash-object "$repo_root/$path")
    else
      digest=deleted
    fi
    printf '%s\0%s\0' "$path" "$digest"
  done
} | git hash-object --stdin
