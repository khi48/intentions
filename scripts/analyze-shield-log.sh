#!/usr/bin/env bash
#
# analyze-shield-log.sh — score a log against the #13 T-matrix evidence
# checklist. Emits one section per check; user picks pass/fail.
#
# Usage:
#   scripts/analyze-shield-log.sh                      # newest log in ~/Downloads/ios-logs
#   scripts/analyze-shield-log.sh <log-path>
#   scripts/analyze-shield-log.sh <log-path> <T>       # ±5min window around HH:MM[:SS]

set -uo pipefail

LOG="${1:-}"
if [[ -z "$LOG" ]]; then
  LOG=$(ls -t "$HOME/Downloads/ios-logs"/*-all.log 2>/dev/null | head -1 || true)
fi
[[ -f "$LOG" ]] || { echo "no log file found: ${LOG:-<none>}" >&2; exit 1; }

T="${2:-}"
WINDOW_START=""
WINDOW_END=""
if [[ -n "$T" ]]; then
  DATE=$(awk 'NR==2 {print $1; exit}' "$LOG")
  [[ "$T" =~ ^[0-9]{2}:[0-9]{2}$ ]] && T="${T}:00"
  START_HMS=$(date -j -v-5M -f '%H:%M:%S' "$T" '+%H:%M:%S' 2>/dev/null || echo "$T")
  END_HMS=$(date -j -v+5M -f '%H:%M:%S' "$T" '+%H:%M:%S' 2>/dev/null || echo "$T")
  WINDOW_START="$DATE $START_HMS"
  WINDOW_END="$DATE $END_HMS"
fi

slice() {
  if [[ -n "$WINDOW_START" ]]; then
    awk -v s="$WINDOW_START" -v e="$WINDOW_END" '$1" "$2 >= s && $1" "$2 <= e' "$LOG"
  else
    cat "$LOG"
  fi
}

# strip "YYYY-MM-DD " date prefix and any " Df|I|E " level, leaving HH:MM:SS.NNN + rest
fmt() { sed -E 's/^[0-9-]{10} ([0-9:.]+) [DIEAW]?[a-z]? +/  \1  /'; }

hr() { printf '\n── %s ──\n' "$*"; }

printf 'Log:    %s\n' "$LOG"
printf 'Size:   %s lines\n' "$(wc -l < "$LOG" | tr -d ' ')"
printf 'Range:  %s → %s\n' \
  "$(awk 'NR==2 {print $1" "$2; exit}' "$LOG")" \
  "$(tail -1 "$LOG" | awk '{print $1" "$2}')"
[[ -n "$T" ]] && printf 'Filter: ±5min around %s\n' "$T"

hr "1. Boundary fires + handleScheduleTransition (direction inferred from 'applying ...')"
slice | grep -E "(intervalDidStart|intervalDidEnd|handleScheduleTransition|handleExpiry)" \
      | grep -v 'PERF: Received' \
      | fmt

hr "2. Extension ManagedSettings writes (container oh.Intent.IntentDeviceActivityMonitor)"
slice | grep -E "IntentionsDeviceActivityMonitor\[[0-9]+:[^]]+\].*ManagedSettings:interface\] (Deleting|Setting values|Clearing all settings|Successfully)" \
      | fmt | head -20

hr "3. Main-app ManagedSettings writes (container oh.Intent — main app wrote)"
slice | grep -E "Intentions\[[0-9]+:[^]]+\].*ManagedSettings:interface\] (Deleting|Setting values|Clearing all settings)" \
      | grep -v IntentionsDeviceActivityMonitor \
      | fmt | head -20

hr "4. oh.Intent force-quit (user-quit 0xdeadfa11)"
slice | grep -E "FrontBoard:Process.*app<oh\.Intent.*user-quit\(0xdeadfa11\)" \
      | fmt

hr "5. Main-app launches + lifecycle"
slice | grep -E "Bootstrapping app<oh\.Intent>|scenePhase → active|catchUpOnForeground (called|: applying)|reapplyCurrentState (called|: applying)" \
      | fmt

hr "6. IntentShieldConfiguration extension launches (shield-render = shield UP)"
COUNT=$(slice | grep -cE "Sending launch request:.*IntentShieldConfiguration|Sending launch request:.*IntentionsShieldConfiguration")
printf '  %s launch(es)\n' "${COUNT:-0}"
slice | grep -E "Sending launch request:.*IntentShieldConfiguration|Sending launch request:.*IntentionsShieldConfiguration" \
      | fmt

hr "7. Target-app launches (probe candidates)"
slice | grep -E "Sending launch request: <RBSLaunchRequest\| app<com\.(hammerandchisel|burbn|facebook|reddit|twitter|tiktok|google|amazon|netflix|youtube|spotify|whatsapp|telegram|snapchat)" \
      | sed -E 's/^[0-9-]{10} ([0-9:.]+).*<RBSLaunchRequest\| (app<[^(]+).*$/  \1  \2>/' \
      | sort -u

hr "8. Darwin wake activity (NEW build expects ABSENT)"
DARWIN=$(slice | grep -cE "Darwin wake → ShieldEngine|darwin\.posted|darwin\.received|darwin\.observerInstalled")
if [[ "${DARWIN:-0}" -gt 0 ]]; then
  printf '  ⚠  %s Darwin lines — wake chain still active, likely stale build\n' "$DARWIN"
  slice | grep -E "Darwin wake → ShieldEngine|darwin\.posted|darwin\.received|darwin\.observerInstalled" | fmt | head -5
else
  printf '  none ✓\n'
fi

hr "9. ManagedSettings broadcast (Notifying clients of changes in [shield])"
BC=$(slice | grep -cE "Notifying clients of changes in")
printf '  %s match(es)\n' "${BC:-0}"
slice | grep -E "Notifying clients of changes in" | fmt | head -5

hr "10. UsageTrackingAgent boundary notify (paired with extension fire)"
slice | grep -E "UsageTrackingAgent.*Notifying extension.*shieldstate\." | fmt | sort -u | head -10

printf '\nDone.\n'
