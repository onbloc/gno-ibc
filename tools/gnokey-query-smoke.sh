#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/tools/gnokey-smoke/run-query-smoke.sh"
"$ROOT/tools/gnokey-smoke/run-zkgm-native-refund.sh"

echo "all smoke assertions passed"
