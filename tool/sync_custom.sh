#!/usr/bin/env bash
#
# BaoCode 2: take what changed upstream, test it, build the app, and put it
# in /Applications/BaoCode 2.app.
#
#   tool/sync_custom.sh                 merge upstream, test, build, install
#   tool/sync_custom.sh --no-tests      skip the test suite
#   tool/sync_custom.sh --build-only    build and package, do not install
#   tool/sync_custom.sh --stash         stash uncommitted changes while merging
#   tool/sync_custom.sh --force         rebuild even when upstream is unchanged
#   tool/sync_custom.sh --carry-remote  put the remote server's builds in
#                                       the app instead of reusing the
#                                       published one
#   tool/sync_custom.sh --install-only  install what is built already, and
#                                       nothing else (tool/in_app_update.sh)
#
# The merge is a normal merge, not a rebase: the branch may already be
# pushed. A conflict stops before anything is built or installed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# This machine's signing identity, if it has one: signing every build with
# the same certificate keeps the app's privacy grants (macOS TCC) across
# rebuilds. Not kept in the repository (tool/custom-signing.env).
if [ -f "$ROOT/tool/custom-signing.env" ]; then
  # shellcheck disable=SC1091
  . "$ROOT/tool/custom-signing.env"
fi

# create-dmg's window, laid out in Finder, pops up at whoever is using the
# machine; a local build skips it (BAOCODE_DMG_PRETTY=1 brings it back).
export BAOCODE_DMG_PRETTY="${BAOCODE_DMG_PRETTY:-0}"

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/baocode-dev/baocode.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
DEST="${BAOCODE2_APP:-/Applications/BaoCode 2.app}"
BACKUP_DIR="${BAOCODE2_BACKUP_DIR:-/private/tmp}"
BUNDLE_ID="dev.baocode.desktop.baocode2"

INSTALL=1
RUN_TESTS=1
STASH=0
FORCE=0
CARRY_REMOTE=0
INSTALL_ONLY=0

usage() {
  sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for argument in "$@"; do
  case "$argument" in
    --no-install|--build-only) INSTALL=0 ;;
    --no-tests) RUN_TESTS=0 ;;
    --stash) STASH=1 ;;
    --force) FORCE=1 ;;
    --carry-remote) CARRY_REMOTE=1 ;;
    --install-only) INSTALL_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $argument" >&2; usage >&2; exit 1 ;;
  esac
done

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

for command in git flutter dart; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Cannot find $command. Set PATH, or FLUTTER's bin, and try again." >&2
    exit 1
  fi
done

if [ -z "${DEVELOPER_DIR:-}" ] &&
  [ -d /Volumes/MacMini/Applications/Xcode.app/Contents/Developer ]; then
  export DEVELOPER_DIR=/Volumes/MacMini/Applications/Xcode.app/Contents/Developer
fi

export FLUTTER_SUPPRESS_ANALYTICS=true

cd "$ROOT"

install_built() {
  source_app="$ROOT/build/macos/thin/arm64/BaoCode.app"
  if [ ! -d "$source_app" ]; then
    echo "The arm64 build was not made: $source_app is missing." >&2
    exit 5
  fi

  built_id="$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleIdentifier' \
    "$source_app/Contents/Info.plist")"
  if [ "$built_id" != "$BUNDLE_ID" ]; then
    echo "The build has bundle identifier $built_id, not $BUNDLE_ID." >&2
    exit 6
  fi

  dmg="$(ls -t "$ROOT"/build/installers/BaoCode-*-arm64.dmg 2>/dev/null | head -1)"
  echo "==> Built${dmg:+: $dmg}"

  if [ "$INSTALL" = 0 ]; then
    exit 0
  fi

  if pgrep -f "$DEST/Contents/MacOS" >/dev/null 2>&1; then
    echo "BaoCode 2 is running. Quit it, then run this script again," >&2
    echo "or use --build-only to leave the new build ready in build/." >&2
    exit 7
  fi

  stamp="$(date +%Y%m%d-%H%M%S)"
  backup="$BACKUP_DIR/BaoCode-2-previous-$stamp.app"
  if [ -e "$DEST" ]; then
    mv "$DEST" "$backup"
    echo "==> Previous version: $backup"
  fi

  if ! ditto "$source_app" "$DEST"; then
    if [ -e "$backup" ]; then mv "$backup" "$DEST"; fi
    echo "Could not copy the new build; the previous version is back." >&2
    exit 8
  fi

  touch "$DEST"
  register=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  if [ -x "$register" ]; then
    "$register" -f "$DEST" || true
  fi

  echo "==> Installed $DEST"
}

if [ "$INSTALL_ONLY" = 1 ]; then
  install_built
  exit 0
fi

if [ -n "$(git status --porcelain)" ]; then
  if [ "$STASH" = 1 ]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    git stash push --include-untracked --message "baocode2-sync-$stamp"
    STASHED=1
    restore_stash() {
      if [ "${STASHED:-0}" = 1 ] && git stash pop; then
        STASHED=0
      fi
    }
  else
    echo "The working tree has uncommitted changes:" >&2
    git status --short >&2
    echo "" >&2
    echo "Commit them, or run with --stash to carry them across the merge." >&2
    exit 2
  fi
else
  restore_stash() { :; }
fi

trap 'if [ "${STASHED:-0}" = 1 ]; then echo "Your changes are still in \`git stash list\`." >&2; fi' EXIT

echo "==> Fetching upstream ($UPSTREAM_URL $UPSTREAM_BRANCH)"
git fetch --no-tags "$UPSTREAM_URL" "$UPSTREAM_BRANCH"
upstream="$(git rev-parse FETCH_HEAD)"

if [ "$FORCE" = 0 ] && git merge-base --is-ancestor "$upstream" HEAD; then
  echo "Upstream has nothing new. Use --force to rebuild anyway."
  restore_stash
  STASHED=0
  exit 0
fi

echo "==> Merging upstream into $(git branch --show-current)"
# A fork that never took the upstream's history (unrelated roots) is merged
# once; after that the two share it.
merge_flags=(--no-edit)
if ! git merge-base HEAD "$upstream" >/dev/null 2>&1; then
  merge_flags+=(--allow-unrelated-histories)
fi
if ! git merge "${merge_flags[@]}" "$upstream"; then
  git merge --abort || true
  echo "" >&2
  echo "Upstream conflicts with the local changes; nothing was built." >&2
  echo "Resolve the conflict by hand, then run this script again." >&2
  restore_stash
  STASHED=0
  exit 3
fi

restore_stash
if [ "${STASHED:-0}" = 1 ]; then
  echo "The merge is done, but restoring your changes conflicted." >&2
  echo "Resolve it by hand; they are still in \`git stash list\`." >&2
  exit 4
fi

if [ "$RUN_TESTS" = 1 ]; then
  echo "==> Testing"
  flutter test --reporter compact
fi

echo "==> Building"
# The remote server's build is not published for a custom build. Reuse the
# one published for this release, so nothing is downloaded and no host is
# sent a second build: the original app's, when it is the same release, else
# the one reused last time (a later release of that app says nothing of
# this one), else our own, carried in the app.
remote_flags=(--carry-remote)
remembered="$HOME/Library/Application Support/BaoCode2/remote-version"
protocol=""
version_in() {
  if [ -f "$1" ]; then awk 'NR == 1 { print $1 }' "$1"; fi
}
# The protocol an app and its server speak (packages/bao_remote/lib/src/
# protocol.dart). A server published for the same version is reused only
# while this is the one it was reused at: a commit that changed it changed
# what the two may say, version number or no.
protocol_of() {
  git show "$1:packages/bao_remote/lib/src/protocol.dart" 2>/dev/null |
    sed -n 's/.*static const version = \([0-9][0-9]*\).*/\1/p' | head -1
}
if [ "$CARRY_REMOTE" = 0 ]; then
  app_version="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)"
  release_prefix="${app_version%%+*}"
  release_build="${app_version#*+}"
  [ "$release_build" = "$app_version" ] && release_build=0
  wanted="${release_prefix}.${release_build}"
  protocol="$(protocol_of HEAD)"
  remembered_version=""
  remembered_protocol=""
  if [ -f "$remembered" ]; then
    read -r remembered_version remembered_protocol <"$remembered" || true
  fi
  published_version=""
  for candidate in \
    "$(version_in /Applications/BaoCode.app/Contents/Resources/remote/VERSION)" \
    "$(version_in build/remote-release/VERSION)" \
    "$(version_in "$remembered")"; do
    if [ -n "$candidate" ] && [ "${candidate%%-*}" = "$wanted" ]; then
      published_version="$candidate"
      break
    fi
  done
  # None names this release: ask what is published now (a release published
  # after this app's own builds, say), rather than carrying for nothing.
  if [ -z "$published_version" ]; then
    echo "  Remote server: asking dl.baocode.dev for the newest published"
    if dart run tool/fetch_remote_server.dart latest \
      --out build/remote-release >/dev/null 2>&1; then
      candidate="$(version_in build/remote-release/VERSION)"
      if [ -n "$candidate" ] && [ "${candidate%%-*}" = "$wanted" ]; then
        published_version="$candidate"
      fi
    fi
  fi
  if [ -n "$published_version" ] &&
    [ -n "$remembered_protocol" ] && [ -n "$protocol" ] &&
    [ "$remembered_protocol" != "$protocol" ]; then
    echo "  $remembered_version's server speaks protocol" \
      "$remembered_protocol, this build $protocol: not reused"
    published_version=""
  fi
  if [ -n "$published_version" ]; then
    echo "  Remote server: reusing $published_version"
    remote_flags=(--remote-release "$published_version")
  fi
fi
if ! dart run tool/build_macos.dart "${remote_flags[@]}"; then
  if [ "${remote_flags[0]}" != --remote-release ]; then
    exit 1
  fi
  # Published once, gone now (or never for this build): carry our own.
  echo "  ${remote_flags[1]} is not served; carrying this build's own" >&2
  remote_flags=(--carry-remote)
  dart run tool/build_macos.dart "${remote_flags[@]}"
fi
if [ "${remote_flags[0]}" = --remote-release ]; then
  mkdir -p "$(dirname "$remembered")"
  printf '%s %s\n' "${remote_flags[1]}" "$protocol" >"$remembered"
elif [ -f "$remembered" ]; then
  # Carried our own: nothing published was reused, so what was remembered
  # names an older release and would only be looked at again to be refused.
  rm -f "$remembered"
fi

# create-dmg mounts a staging image to lay its window out; one it leaves
# mounted keeps a Finder window around, which pops up beside the app.
for mounted in /Volumes/dmg.*; do
  [ -d "$mounted" ] || continue
  hdiutil detach "$mounted" -force >/dev/null 2>&1 || true
done

install_built
