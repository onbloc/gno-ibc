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
    build_args=(--target gno)
    ;;
  voyager)
    repository=${E2E_VOYAGER_REPOSITORY:-$namespace/gno-ibc-e2e-voyager}
    union_dir=${UNION_VOYAGER_DIR:?set UNION_VOYAGER_DIR to the pinned checkout}
    union_revision=${UNION_VOYAGER_REVISION:?set UNION_VOYAGER_REVISION}
    build_args=(
      --target voyager
      --build-context "union-src=$union_dir"
      --build-arg "UNION_COMMIT=$union_revision"
    )
    ;;
  *)
    echo "usage: $0 gno|voyager [--load|--push]" >&2
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
tag=${E2E_IMAGE_TAG:-$(git -C "$repo_root" rev-parse HEAD)}
image="$registry/$repository:$tag"
cache="$registry/$repository:buildcache"

if docker buildx imagetools inspect "$image" >/dev/null 2>&1; then
  docker pull "$image" >/dev/null
elif docker image inspect "$image" >/dev/null 2>&1; then
  if [[ $output == --push ]]; then
    docker push "$image" >&2
  fi
else
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

printf '%s\n' "$image"
