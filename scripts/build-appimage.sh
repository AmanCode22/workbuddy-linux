#!/usr/bin/env bash
# Build the AppImage (x86_64). Requires appimagetool on PATH
# (https://github.com/AppImage/appimagetool/releases - run with --appimage-extract
#  if FUSE is unavailable: ./appimagetool-*.AppImage --appimage-extract).
# Env: STAGE, OUT, VER
set -euo pipefail
STAGE="${STAGE:?set STAGE}"
OUT="${OUT:?set OUT}"
VER="${VER:?set VER}"
APPDIR="$(mktemp -d)"
trap 'rm -rf "$APPDIR"' EXIT

mkdir -p "$APPDIR/opt" "$APPDIR/usr/share/icons/hicolor/512x512/apps"
cp -a "$STAGE/opt/WorkBuddy AI" "$APPDIR/opt/WorkBuddy AI"

cat > "$APPDIR/workbuddyai.desktop" <<'EOF'
[Desktop Entry]
Name=WorkBuddy AI
Exec=AppRun %U
Terminal=false
Type=Application
Icon=workbuddyai
StartupWMClass=WorkBuddy AI
Comment=WorkBuddy Desktop - AI Agent Desktop Application
MimeType=x-scheme-handler/workbuddy-ai;
Categories=Development;
EOF
cp "$STAGE/usr/share/icons/hicolor/512x512/apps/workbuddyai.png" "$APPDIR/workbuddyai.png"
cp "$STAGE/usr/share/icons/hicolor/512x512/apps/workbuddyai.png" \
   "$APPDIR/usr/share/icons/hicolor/512x512/apps/workbuddyai.png"
ln -sf workbuddyai.png "$APPDIR/.DirIcon"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/bash
# WorkBuddy AI AppRun — community Linux port
APPDIR="$(dirname "$(readlink -f "$0")")"
BIN="$APPDIR/opt/WorkBuddy AI/workbuddyai"

SANDBOX_FLAG=(--no-sandbox)
SANDBOX="$APPDIR/opt/WorkBuddy AI/chrome-sandbox"
# only rely on the setuid chrome-sandbox when it is actually usable
# (AppImages are usually mounted nosuid)
if [ -u "$SANDBOX" ] && [ "$(stat -f -c %T "$APPDIR")" != "fuseblk.squashfs" ]; then
  SANDBOX_FLAG=()
fi

export TMPDIR="${TMPDIR:-/tmp}"
exec "$BIN" "${SANDBOX_FLAG[@]}" "$@"
EOF
chmod 755 "$APPDIR/AppRun"

if command -v appimagetool >/dev/null 2>&1; then
  appimagetool "$APPDIR" "$OUT/WorkBuddy-$VER-linux-x86_64.AppImage"
elif [[ -x "$HOME/squashfs-root/AppRun" ]]; then
  "$HOME/squashfs-root/AppRun" "$APPDIR" "$OUT/WorkBuddy-$VER-linux-x86_64.AppImage"
else
  echo "appimagetool not found" >&2; exit 1
fi
echo "[appimage] $(ls -lh "$OUT"/WorkBuddy-$VER-linux-x86_64.AppImage)"
