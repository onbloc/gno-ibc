#!/bin/bash
# Wrapper script to run docker compose from the correct directory
# Usage: ./docker-compose-cmd.sh [docker-compose args...]

cd "$(dirname "$0")" || exit 1
docker compose "$@"
