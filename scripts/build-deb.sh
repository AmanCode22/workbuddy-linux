#!/usr/bin/env bash
# Build the DEB (amd64). Mirrors the official Tencent workbuddyai deb metadata.
# Env: STAGE (assembled tree), OUT, VER
set -euo pipefail
STAGE="${STAGE:?set STAGE}"
OUT="${OUT:?set OUT}"
VER="${VER:?set VER}"
PACKAGER="${PACKAGER:-AmanCode22 <amanady125@gmail.com>}"

CTRL="$STAGE/DEBIAN"
mkdir -p "$CTRL"
cat > "$CTRL/control" <<EOF
Package: workbuddyai
Version: $VER
License: unknown
Vendor: Tencent Technology (Shenzhen) Company Limited <workbuddy@tencent.com>
Architecture: amd64
Maintainer: $PACKAGER
Installed-Size: $(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)
Depends: libgtk-3-0, libnotify4, libnss3, libxss1, libxtst6, xdg-utils, libatspi2.0-0, libuuid1, libsecret-1-0
Recommends: libappindicator3-1, imagemagick
Section: default
Priority: optional
Homepage: https://www.workbuddy.ai
Description: WorkBuddy Desktop - AI Agent Desktop Application
 Full-scenario AI office agent workbench by the Tencent CodeBuddy team.
 Unofficial native Linux port of $VER (x86_64). Port by $PACKAGER.
EOF

cat > "$CTRL/postinst" <<'EOF'
#!/bin/bash
# setuid sandbox so Electron can use the Chrome sandbox without --no-sandbox
if [ -e "/opt/WorkBuddy AI/chrome-sandbox" ]; then
  chown root:root "/opt/WorkBuddy AI/chrome-sandbox" || true
  chmod 4755 "/opt/WorkBuddy AI/chrome-sandbox" || true
fi
command -v update-desktop-database >/dev/null 2>&1 && \
  update-desktop-database -q /usr/share/applications || true
exit 0
EOF
chmod 755 "$CTRL/postinst"

dpkg-deb --root-owner-group --build -Zxz "$STAGE" \
  "$OUT/workbuddyai-$VER-linux-amd64.deb"
echo "[deb] $(ls -lh "$OUT"/workbuddyai-$VER-linux-amd64.deb)"
