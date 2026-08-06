#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
repo_root=$(cd "$script_dir/../.." && pwd -P)
component=${1:-}
output=${2:---load}
namespace=${E2E_IMAGE_NAMESPACE:-onbloc}

case "$component" in
  gno)
    repository=${E2E_GNO_REPOSITORY:-$namespace/gno-ibc-e2e-gno}
    ;;
  voyager)
    repository=${E2E_VOYAGER_REPOSITORY:-$namespace/gno-ibc-e2e-voyager}
    ;;
  union-deployer)
    repository=${E2E_UNION_DEPLOYER_REPOSITORY:-$namespace/gno-ibc-e2e-union-deployer}
    ;;
  *)
    echo "usage: $0 gno|voyager|union-deployer [--load|--push]" >&2
    exit 2
    ;;
esac

case "$output" in
  --load|--push) ;;
  *)
    echo "output must be --load or --push" >&2
    exit 2
    ;;
esac

registry=${E2E_REGISTRY:?set E2E_REGISTRY to the container registry hostname}
tag=${E2E_IMAGE_TAG:-$("$script_dir/image-tag.sh" "$component")}
image="$registry/$repository:$tag"
cache="$registry/$repository:buildcache"

if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
  docker pull "$image" >/dev/null
elif docker image inspect "$image" >/dev/null 2>&1; then
  if [[ $output == --push ]]; then
    docker push "$image" >&2
  fi
else
  if [[ $component == union-deployer ]]; then
    union_dir=${UNION_VOYAGER_DIR:?set UNION_VOYAGER_DIR to the pinned checkout}
    union_revision=${UNION_VOYAGER_REVISION:?set UNION_VOYAGER_REVISION}
    [[ $tag =~ ^[0-9a-f]{40}$ ]] || {
      echo "union-deployer image tag must be a content hash" >&2
      exit 1
    }
    git -C "$union_dir" cat-file -e "$union_revision^{commit}"
    build_dir=$(mktemp -d)
    cleanup() {
      git -C "$union_dir" worktree remove --force "$build_dir/union" >/dev/null 2>&1 || true
      rm -rf "$build_dir"
    }
    trap cleanup EXIT
    git -C "$union_dir" worktree add --detach "$build_dir/union" "$union_revision" >&2
    git -C "$build_dir/union" apply "$script_dir/union-deployer-trusted-mpt.patch"
    docker run --rm --network host \
      -v "$build_dir/union:/work/union:ro" \
      -v "$script_dir/union-deployer.nix:/work/union-deployer.nix:ro" \
      -v "$build_dir:/work/output" \
      -v union-deployer-nix-store-x86_64-linux:/nix \
      -v union-deployer-nix-cache-x86_64-linux:/root/.cache/nix \
      -e NIX_CONFIG='experimental-features = nix-command flakes' \
      nixos/nix:latest sh -lc '
        nix --accept-flake-config build --impure \
          --expr "import /work/union-deployer.nix {
            unionRoot = /work/union;
            imageTag = \"$1\";
            revision = \"$2\";
          }" \
          --out-link /tmp/union-deployer-image
        cp -L /tmp/union-deployer-image /work/output/image.tar
      ' union-deployer-image "$tag" "$union_revision" >&2
    docker load --input "$build_dir/image.tar" >&2
    docker tag "union-deployer:$tag" "$image"
    if [[ $output == --push ]]; then
      docker push "$image" >&2
    fi
  else
    if [[ $component == gno ]]; then
      make -C "$repo_root" vendor >&2
      build_args=(--target gno)
    else
      union_dir=${UNION_VOYAGER_DIR:?set UNION_VOYAGER_DIR to the pinned checkout}
      union_revision=${UNION_VOYAGER_REVISION:?set UNION_VOYAGER_REVISION}
      build_args=(
        --target voyager
        --build-context "union-src=$union_dir"
        --build-arg "UNION_COMMIT=$union_revision"
      )
    fi
    cache_args=(--progress plain)
    if docker buildx imagetools inspect "$cache" >/dev/null 2>&1; then
      cache_args+=(--cache-from "type=registry,ref=$cache")
    fi
    if [[ $output == --push ]]; then
      cache_args+=(--cache-to "type=registry,ref=$cache,mode=max")
    fi
    docker buildx build \
      "${build_args[@]}" \
      "${cache_args[@]}" \
      "$output" \
      --tag "$image" \
      --file "$script_dir/Dockerfile" \
      "$repo_root" >&2
  fi
fi

printf '%s\n' "$image"
