#!/usr/bin/env bash
# Build the Flatpak bundle (.flatpak single-file). Requires flatpak + flatpak-builder.
#   sudo apt install flatpak flatpak-builder   (CI)
# Env: STAGE (assembled tree), OUT, VER, REPO_ROOT
set -euo pipefail
STAGE="${STAGE:?set STAGE}"
OUT="${OUT:?set OUT}"
VER="${VER:-5.9.4}"
REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FP="$REPO_ROOT/packaging/flatpak"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

# stage the flatpak module sources
mkdir -p "$BUILD/app" "$BUILD/icons-prepared"
cp -a "$STAGE/opt/WorkBuddy AI/." "$BUILD/app/"
for s in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
  mkdir -p "$BUILD/icons-prepared/$s"
  cp "$STAGE/usr/share/icons/hicolor/$s/apps/workbuddyai.png" "$BUILD/icons-prepared/$s/"
done
cp "$REPO_ROOT/packaging/workbuddyai.desktop" "$FP/com.tencent.WorkBuddy.json" "$BUILD/"
sed "s/5\.9\.4/$VER/g" "$FP/metainfo.xml" > "$BUILD/metainfo.xml"

flatpak remote-add --user --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --user -y --noninteractive flathub \
  org.freedesktop.Sdk//25.08 org.freedesktop.Platform//25.08

cd "$BUILD"
flatpak-builder --user --force-clean --disable-rofiles-fuse \
  --repo=fp-repo --install-deps-from=flathub fp-build com.tencent.WorkBuddy.json
flatpak build-bundle fp-repo "$OUT/WorkBuddy-$VER-linux-x86_64.flatpak" \
  com.tencent.WorkBuddy "$VER"
echo "[flatpak] $(ls -lh "$OUT"/*.flatpak)"
