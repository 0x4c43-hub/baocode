#!/usr/bin/env bash
#
# BaoCode 2 自动更新：看上游 baocode 有没有新提交，有就合并、测试、构建，
# 并在 BaoCode 2 没在运行时装上（tool/sync_custom.sh 做合并与构建）。
#
#   tool/autoupdate_custom.sh            检查并更新
#   tool/autoupdate_custom.sh --check    只检查，说出上游有没有更新
#   tool/autoupdate_custom.sh --no-tests 更新但不跑测试
#   tool/autoupdate_custom.sh --quiet    没有更新时不输出（定时任务用）
#
# 工作区有未提交的改动时跳过：自动合并会把还没提交的工作搅乱。
# 合并冲突时 git merge --abort，然后停下，不构建也不安装。
# 新版本构建好而 BaoCode 2 正在运行：只留下构建结果，退出运行
# （或下一次检查、登录）时再装。
#
# tool/install_autoupdate.sh 把它装成每天一次的 LaunchAgent。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/baocode-dev/baocode.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
DEST="${BAOCODE2_APP:-/Applications/BaoCode 2.app}"
LOG="${BAOCODE2_AUTOUPDATE_LOG:-$HOME/Library/Logs/BaoCode2-autoupdate.log}"
PENDING="$ROOT/build/installers/pending-install"
LOCK="${TMPDIR:-/tmp}/baocode2-autoupdate.lock"

CHECK_ONLY=0
RUN_TESTS=1
QUIET=0

for argument in "$@"; do
  case "$argument" in
    --check) CHECK_ONLY=1 ;;
    --no-tests) RUN_TESTS=0 ;;
    --quiet) QUIET=1 ;;
    -h|--help) sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $argument" >&2; exit 1 ;;
  esac
done

mkdir -p "$(dirname "$LOG")"
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"
}

notify() {
  # 只在有人登录的图形会话里弹通知；SSH、cron 里没有。
  osascript -e "display notification \"$1\" with title \"BaoCode 2 自动更新\"" \
    >/dev/null 2>&1 || true
}

if ! mkdir "$LOCK" 2>/dev/null; then
  log "Another run is under way ($LOCK); leaving."
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

if ! command -v flutter >/dev/null 2>&1; then
  for candidate in \
    /private/tmp/baocode-build-tools/flutter/bin \
    "$HOME/flutter/bin" \
    /opt/homebrew/bin; do
    if [ -x "$candidate/flutter" ]; then
      PATH="$candidate:$PATH"
      break
    fi
  done
fi
export FLUTTER_SUPPRESS_ANALYTICS=true
if [ -z "${DEVELOPER_DIR:-}" ] &&
  [ -d /Volumes/MacMini/Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Volumes/MacMini/Applications/Xcode.app/Contents/Developer
fi

cd "$ROOT"

running() { pgrep -f "$DEST/Contents/MacOS" >/dev/null 2>&1; }

# A build made while BaoCode 2 was running is put in place at the next run.
if [ -f "$PENDING" ] && ! running; then
  log "Installing the build left ready last time"
  if tool/sync_custom.sh --install-only >>"$LOG" 2>&1; then
    rm -f "$PENDING"
    notify "已安装新版本，重新打开 BaoCode 2 即可"
  else
    log "The install failed; see the log above."
  fi
fi

log "Checking $UPSTREAM_URL ($UPSTREAM_BRANCH)"
git fetch --no-tags "$UPSTREAM_URL" "$UPSTREAM_BRANCH" >>"$LOG" 2>&1
upstream="$(git rev-parse FETCH_HEAD)"

if git merge-base --is-ancestor "$upstream" HEAD; then
  [ "$QUIET" = 1 ] || log "Up to date ($(git rev-parse --short HEAD))"
  exit 0
fi

version="$(git show "$upstream:pubspec.yaml" |
  sed -n 's/^version:[[:space:]]*//p' | head -1)"
commits="$(git rev-list --count "HEAD..$upstream")"
log "Upstream has $commits new commit(s), $version ($(git rev-parse --short "$upstream"))"

if [ "$CHECK_ONLY" = 1 ]; then
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  log "The working tree has uncommitted changes; not merging."
  notify "上游有 $commits 个新提交（$version），但工作区有未提交的改动，已跳过"
  exit 10
fi

notify "发现上游 $commits 个新提交（$version），开始构建"

flags=()
[ "$RUN_TESTS" = 0 ] && flags+=(--no-tests)
if running; then
  # Building does not touch the app in use; it is installed once quit.
  log "BaoCode 2 is running: building, installing when it quits"
  mkdir -p "$(dirname "$PENDING")"
  touch "$PENDING"
  if tool/sync_custom.sh --build-only "${flags[@]}" >>"$LOG" 2>&1; then
    notify "新版本已构建，退出 BaoCode 2 后自动安装"
  else
    rm -f "$PENDING"
    log "The build failed; see the log above."
    notify "构建失败，详情见 ~/Library/Logs/BaoCode2-autoupdate.log"
    exit 11
  fi
else
  if tool/sync_custom.sh "${flags[@]}" >>"$LOG" 2>&1; then
    notify "已更新到 $version"
  else
    log "The update failed; see the log above."
    notify "更新失败，详情见 ~/Library/Logs/BaoCode2-autoupdate.log"
    exit 11
  fi
fi
