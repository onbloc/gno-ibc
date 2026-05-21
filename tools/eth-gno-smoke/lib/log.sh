#!/usr/bin/env bash
# log.sh — log-field extraction and assertion helpers for smoke runners.

capture_field() {
  local name="$1"
  local file="$2"
  awk -v key="$name" '$1 == key { print $2; exit }' "$file"
}

require_field() {
  local name="$1"
  local file="$2"
  local value
  value="$(capture_field "$name" "$file")"
  if [[ -z "$value" ]]; then
    echo "FAIL: missing '$name' in $file"
    cat "$file"
    exit 1
  fi
  printf "%s" "$value"
}

require_log_line() {
  local pattern="$1"
  local file="$2"
  local msg="$3"
  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $msg"
    cat "$file"
    exit 1
  fi
}
