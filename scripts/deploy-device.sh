#!/usr/bin/env bash
#
# deploy-device.sh — thin wrapper around the shared iOS deploy script.
# Real implementation: Mind/scripts/ios/deploy-device.sh
#
# Usage:
#   scripts/deploy-device.sh                # full: build → install → launch
#   scripts/deploy-device.sh --no-launch    # skip launch
#   scripts/deploy-device.sh --no-build     # use last build (faster on reinstall)
#   scripts/deploy-device.sh --device <id>  # force a specific device identifier

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHARED="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Mind/scripts/ios/deploy-device.sh"

if [[ ! -x "$SHARED" ]]; then
  echo "shared deploy script not found or not executable: $SHARED" >&2
  echo "vault may not be synced on this machine" >&2
  exit 1
fi

exec "$SHARED" \
  --scheme    Intentions \
  --bundle-id oh.Intent \
  --config    Debug \
  --project-root "$PROJECT_ROOT" \
  "$@"
