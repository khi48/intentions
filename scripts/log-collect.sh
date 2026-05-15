#!/usr/bin/env bash
#
# log-collect.sh — thin wrapper around the shared iOS log-collect script.
# Real implementation: Mind/scripts/ios/log-collect.sh
#
# Usage:
#   scripts/log-collect.sh                            # last 30m, archive only
#   scripts/log-collect.sh --last 1h                  # custom window
#   scripts/log-collect.sh --extract bgtask           # archive + filtered .log
#   scripts/log-collect.sh --extract shieldstate      # Intent / Family Controls / ManagedSettings
#   scripts/log-collect.sh --extract all              # bgtask + shieldstate
#
# See the shared script (-h) for full options.

set -euo pipefail

SHARED="$HOME/Library/Mobile Documents/iCloud~md~obsidian/Documents/Mind/scripts/ios/log-collect.sh"

if [[ ! -x "$SHARED" ]]; then
  echo "shared log-collect script not found or not executable: $SHARED" >&2
  echo "vault may not be synced on this machine" >&2
  exit 1
fi

exec "$SHARED" "$@"
