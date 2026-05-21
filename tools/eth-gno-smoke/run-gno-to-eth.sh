#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command gnokey
require_command gnodev

status_incomplete "Gno -> ETH"
