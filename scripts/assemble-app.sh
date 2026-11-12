#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# assemble-app.sh — assemble the native Linux x86_64 WorkBuddy app tree.
#
# Recipe (verified on WorkBuddy 5.9.3 / 5.9.4, Electron 37.10.3):
#   WorkBuddy is an Electron app (electron-builder, NOT Tauri). The official
#   darwin-x64 distribution already ships every Linux prebuilt native module
#   (node-pty-linux-x64, os-bridge-linux-x64-gnu, koffi linux-x64, ...) plus
#   Linux main-process code (update-service.linux.js, appimage-self-update.js).
#
#   Linux port = app.asar + app.asar.unpacked (from the official darwin-x64 zip)
#              + the official Electron linux-x64 runtime of the SAME version.
#
# Output layout (STAGE):
#   opt/WorkBuddy AI/        <- full application
#   opt/WorkBuddy AI/workbuddyai   <- electron binary (renamed)
#   usr/share/applications/workbuddyai.desktop
#   usr/share/icons/hicolor/*/apps/workbuddyai.png
#
# Usage:
#   ./assemble-app.sh --zip WorkBuddy-darwin-x64-<v>.zip [--electron-ver X] \
#                     --stage /path/to/stage [--repo /path/to/repo] [--skip-patch]
#
# If --zip is omitted it is downloaded from the official update API
# (platform=workbuddy-darwin-x64 — the Intel channel).
#
# By default the staged app.asar is patched right after being copied
# (scripts/patch-credential-bootstrap.py: renames WORKBUDDY_AT_REST_ENCRYPTION
# to a same-length dummy key so the bundled CLI starts in "standalone" mode
# instead of failing with CREDENTIAL_BOOTSTRAP_FAILED on vanilla Electron).
# Pass --skip-patch to build without it.
# ---------------------------------------------------------------------------
set -euo pipefail

ZIP=""
STAGE=""
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ELECTRON_VER=""
SKIP_PATCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zip) ZIP="$2"; shift 2 ;;
    --stage) STAGE="$2"; shift 2 ;;
    --electron-ver) ELECTRON_VER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --skip-patch) SKIP_PATCH=1 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$(dirname "$STAGE")"

# --- 1. obtain the official darwin-x64 (Intel) distribution ----------------
if [[ -z "$ZIP" ]]; then
  echo "[assemble] querying update API (platform=workbuddy-darwin-x64)..."
  META="$(curl -fsSL --max-time 60 \
    'https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-x64')"
  ZIP_URL="$(echo "$META" | jq -r .url)"
  echo "[assemble] API version: $(echo "$META" | jq -r .version)"
  echo "[assemble] url: $ZIP_URL"
  ZIP="$WORK/workbuddy-darwin-x64.zip"
  curl -fL --retry 3 --max-time 1200 -o "$ZIP" "$ZIP_URL"
fi

# --- 2. extract ------------------------------------------------------------
SEVENZ="$(command -v 7zz || command -v 7z)"
[[ -n "$SEVENZ" ]] || { echo "need 7zz (7-Zip) on PATH" >&2; exit 1; }
echo "[assemble] extracting darwin-x64 zip..."
# NOTE: 7-Zip exits non-zero because it refuses to recreate 11 macOS-only
# framework symlinks inside the .app bundle ("Dangerous link ... ignored").
# Those are irrelevant to the Linux port; tolerate the exit code but verify
# the files we actually need exist.
"$SEVENZ" x -y -o"$WORK/src" "$ZIP" >"$WORK/extract.log" 2>&1 || \
  echo "[assemble] 7-Zip reported errors (expected: macOS symlink aliases)"
APP_CONTENTS="$WORK/src/WorkBuddy AI.app/Contents"
[[ -f "$APP_CONTENTS/Resources/app.asar" ]] || {
  echo "::error::app.asar missing after extraction — unexpected zip layout" >&2
  tail -20 "$WORK/extract.log" >&2; exit 1; }

# --- 3. pair the matching Electron linux-x64 runtime ------------------------
if [[ -z "$ELECTRON_VER" ]]; then
  ELECTRON_VER="$(python3 - <<EOF
import os, plistlib, sys
paths = [
    "$APP_CONTENTS/Frameworks/Electron Framework.framework/Resources/Info.plist",
    "$APP_CONTENTS/Frameworks/Electron Framework.framework/Versions/A/Resources/Info.plist",
]
for p in paths:
    if os.path.exists(p):
        print(plistlib.load(open(p, "rb"))["CFBundleVersion"])
        sys.exit(0)
sys.exit("Electron Framework Info.plist not found in extracted zip")
EOF
)"
fi
echo "[assemble] upstream Electron version: $ELECTRON_VER"
EZIP="$WORK/electron-linux-x64.zip"
curl -fL --retry 3 --max-time 900 -o "$EZIP" \
  "https://npmmirror.com/mirrors/electron/$ELECTRON_VER/electron-v$ELECTRON_VER-linux-x64.zip"
mkdir -p "$STAGE/opt/WorkBuddy AI"
"$SEVENZ" x -y -o"$STAGE/opt/WorkBuddy AI" "$EZIP" >/dev/null
mv "$STAGE/opt/WorkBuddy AI/electron" "$STAGE/opt/WorkBuddy AI/workbuddyai"
ln -sf workbuddyai "$STAGE/opt/WorkBuddy AI/electron"

# --- 4. drop in the application payload -------------------------------------
cp "$APP_CONTENTS/Resources/app.asar" "$STAGE/opt/WorkBuddy AI/resources/"
cp -a "$APP_CONTENTS/Resources/app.asar.unpacked" "$STAGE/opt/WorkBuddy AI/resources/"

# --- 4b. patch the credential-bootstrap env key (CREDENTIAL_BOOTSTRAP_FAILED fix)
if [[ -n "$SKIP_PATCH" ]]; then
  echo "[assemble] skipping credential-bootstrap patch (--skip-patch)"
else
  python3 "$REPO/scripts/patch-credential-bootstrap.py" \
    "$STAGE/opt/WorkBuddy AI/resources/app.asar"
fi

# --- 5. desktop entry + icons (extracted from the official Linux 5.5.2 deb) --
mkdir -p "$STAGE/usr/share/applications"
cp "$REPO/packaging/workbuddyai.desktop" "$STAGE/usr/share/applications/"
cp -r "$REPO/packaging/icons/hicolor" "$STAGE/usr/share/icons_hicolor.tmp"
mkdir -p "$STAGE/usr/share/icons"
mv "$STAGE/usr/share/icons_hicolor.tmp" "$STAGE/usr/share/icons/hicolor"

# setuid sandbox marker (activated by deb/rpm post-install as root)
chmod 755 "$STAGE/opt/WorkBuddy AI/chrome-sandbox" || true

echo "[assemble] done: $STAGE ($(du -sh "$STAGE" | cut -f1), Electron $ELECTRON_VER)"
