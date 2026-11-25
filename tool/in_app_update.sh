#!/usr/bin/env bash
#
# Runs the custom build's update for the app: merges what changed upstream,
# tests it and builds, then waits for the app to quit, puts the new build in
# place, and opens it again. Settings → Updates starts it (lib/update/
# source_update_controller.dart), and reads its log as it goes.
#
#   tool/in_app_update.sh <app pid> [--no-tests]
#
# Written for that caller: no terminal, so everything goes to the log, and
# the app's markers ("==> Ready", "==> Failed") are what it reads back.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${BAOCODE2_APP:-/Applications/BaoCode 2.app}"
LOG="${BAOCODE2_UPDATE_LOG:-$HOME/Library/Logs/BaoCode2-update.log}"
pid="${1:?the pid of the app}"
shift || true

mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1

say() { printf '%s == %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() {
  say "Failed: $*"
  echo "==> Failed: $*"
  exit 1
}

say "Update for pid $pid, from $ROOT"

tests=()
for argument in "$@"; do
  case "$argument" in
    --no-tests) tests+=(--no-tests) ;;
  esac
done

if ! "$ROOT/tool/sync_custom.sh" --build-only ${tests[@]+"${tests[@]}"}; then
  fail "the build did not finish (see above)"
fi

echo "==> Ready: quit BaoCode 2 to install"
say "Built; waiting for BaoCode 2 to quit"

# The app installs nothing while it runs: it is put in place once it quits,
# as the official update does. A week is as long as waiting means anything.
for _ in $(seq 1 604800); do
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done

if kill -0 "$pid" 2>/dev/null; then
  fail "BaoCode 2 is still running"
fi

say "Quit; installing"
if ! "$ROOT/tool/sync_custom.sh" --install-only; then
  fail "the install did not finish (see above)"
fi

open -a "$DEST" || fail "the new build could not be opened"
echo "==> Installed"
say "Installed and opened"
