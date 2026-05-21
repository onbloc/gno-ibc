#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command gnokey
require_command gnodev

if [[ "${ETH_GNO_SMOKE_REQUIRE_ANVIL:-0}" == "1" ]]; then
  require_command anvil
fi

status_incomplete "ETH -> Gno"
