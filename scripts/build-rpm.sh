#!/usr/bin/env bash
# Build the RPM (x86_64). Requires rpmbuild (apt install rpm / dnf install rpm-build).
# Env: STAGE, OUT, VER
set -euo pipefail
STAGE="${STAGE:?set STAGE}"
OUT="${OUT:?set OUT}"
VER="${VER:?set VER}"
PACKAGER="${PACKAGER:-AmanCode22 <amanady125@gmail.com>}"
TOP="$(mktemp -d)"
trap 'rm -rf "$TOP"' EXIT
mkdir -p "$TOP/SPECS" "$TOP/RPMS" "$TOP/SOURCES" "$TOP/tmp"

cat > "$TOP/workbuddyai.spec" <<SPEC
Name:           workbuddyai
Version:        $VER
Release:        1%{?dist}
Summary:        WorkBuddy Desktop - AI Agent Desktop Application
License:        Commercial
Vendor:         Tencent Technology (Shenzhen) Company Limited
Packager:       $PACKAGER
URL:            https://www.workbuddy.ai
AutoReqProv:    no
BuildArch:      x86_64

%global debug_package %{nil}
%global __os_install_post %{nil}
%global _binary_payload w9.xzdio
%global _binary_filedigest_algorithm sha256

Requires:       gtk3, libnotify, nss, libXScrnSaver, libXtst, xdg-utils, at-spi2-core, libuuid, libsecret
Recommends:     libappindicator-gtk3, ImageMagick

%description
WorkBuddy Desktop - full-scenario AI office agent workbench by the Tencent
CodeBuddy team. Unofficial native Linux x86_64 port. Port by $PACKAGER.

%install
mkdir -p "%{buildroot}/opt"
cp -a "$STAGE/opt/WorkBuddy AI" "%{buildroot}/opt/WorkBuddy AI"
mkdir -p "%{buildroot}/usr/share/applications" "%{buildroot}/usr/share/icons/hicolor"
cp -a "$STAGE/usr/share/applications/." "%{buildroot}/usr/share/applications/"
cp -a "$STAGE/usr/share/icons/hicolor/." "%{buildroot}/usr/share/icons/hicolor/"
chmod 4755 "%{buildroot}/opt/WorkBuddy AI/chrome-sandbox" || true

%clean
rm -rf "%{buildroot}"

%files
"/opt/WorkBuddy AI"
"/usr/share/applications/workbuddyai.desktop"
/usr/share/icons/hicolor/*/apps/workbuddyai.png

%changelog
* Thu Nov 12 2026 $PACKAGER - $VER-1
- Unofficial native Linux port of WorkBuddy $VER (x86_64)
SPEC

cat > "$HOME/.rpmmacros" <<MACROS
%_topdir $TOP
%_tmppath $TOP/tmp
MACROS

rpmbuild -bb --define "stage $STAGE" --define "_topdir $TOP" "$TOP/workbuddyai.spec"
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT/" \;
echo "[rpm] $(ls -lh "$OUT"/*.rpm)"
