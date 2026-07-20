#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
UNION_COMMIT=$(sed -n 's/^UNION_COMMIT=//p' "$script_dir/.env.example")
case $(uname -m) in
	x86_64) checksum_name=TRUSTED_MPT_WASM_SHA256_X86_64 ;;
	aarch64|arm64) checksum_name=TRUSTED_MPT_WASM_SHA256_AARCH64 ;;
	*) echo "unsupported build architecture: $(uname -m)" >&2; exit 2 ;;
esac
TRUSTED_MPT_WASM_SHA256=$(sed -n "s/^$checksum_name=//p" "$script_dir/.env.example")

UNION_VOYAGER_DIR=${UNION_VOYAGER_DIR:-"$script_dir/../../../union-voyager"}
TRUSTED_MPT_WASM=${TRUSTED_MPT_WASM:-"$UNION_VOYAGER_DIR/target/wasm32-unknown-unknown/wasm-release/trusted_mpt_light_client.wasm"}

actual_commit=$(git -C "$UNION_VOYAGER_DIR" rev-parse HEAD)
[ "$actual_commit" = "$UNION_COMMIT" ] || {
  echo "Union checkout is $actual_commit, want $UNION_COMMIT" >&2
  exit 1
}
[ -z "$(git -C "$UNION_VOYAGER_DIR" status --porcelain)" ] || {
  echo "Union checkout must be clean" >&2
  exit 1
}
[ -f "$TRUSTED_MPT_WASM" ] || {
  echo "trusted MPT artifact is missing: $TRUSTED_MPT_WASM" >&2
  exit 1
}

if command -v sha256sum >/dev/null; then
  actual_wasm_sha256=$(sha256sum "$TRUSTED_MPT_WASM" | cut -d ' ' -f 1)
else
  actual_wasm_sha256=$(shasum -a 256 "$TRUSTED_MPT_WASM" | cut -d ' ' -f 1)
fi
[ "$actual_wasm_sha256" = "$TRUSTED_MPT_WASM_SHA256" ] || {
  echo "trusted MPT checksum is $actual_wasm_sha256, want $TRUSTED_MPT_WASM_SHA256" >&2
  exit 1
}

echo "verified Union $UNION_COMMIT and trusted MPT $TRUSTED_MPT_WASM_SHA256"
