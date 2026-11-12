Name:           workbuddyai
Version:        5.9.4
Release:        1%{?dist}
Summary:        WorkBuddy Desktop - AI Agent Desktop Application
License:        Commercial
Vendor:         Tencent Technology (Shenzhen) Company Limited
Packager:       AmanCode22 <amanady125@gmail.com>
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
CodeBuddy team. Linux x86_64 build 5.9.4 assembled from the official
darwin-x64 distribution resources with the official Electron linux-x64
runtime. Community port by AmanCode22 <amanady125@gmail.com>.

%install
mkdir -p "%{buildroot}/opt"
cp -a "$STAGE/opt/WorkBuddy AI" "%{buildroot}/opt/WorkBuddy AI"
mkdir -p "%{buildroot}/usr/share/applications" "%{buildroot}/usr/share/icons/hicolor"
cp -a "$STAGE/usr/share/applications/." "%{buildroot}/usr/share/applications/"
cp -a "$STAGE/usr/share/icons/hicolor/." "%{buildroot}/usr/share/icons/hicolor/"
# setuid sandbox (only effective when rpm is installed as root)
chmod 4755 "%{buildroot}/opt/WorkBuddy AI/chrome-sandbox" || true

%clean
rm -rf "%{buildroot}"

%files
"/opt/WorkBuddy AI"
"/usr/share/applications/workbuddyai.desktop"
/usr/share/icons/hicolor/*/apps/workbuddyai.png

%changelog
* Thu Nov 12 2026 AmanCode22 <amanady125@gmail.com> - 5.9.4-1
- Community Linux port of WorkBuddy 5.9.4 (x86_64)
