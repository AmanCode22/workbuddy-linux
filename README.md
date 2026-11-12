# WorkBuddy AI for Linux (unofficial native port, x86_64)

> Native Linux port of **Tencent WorkBuddy** — the full-scenario AI office agent
> workbench from the CodeBuddy team.
> **Port by AmanCode22** — [amanady125@gmail.com](mailto:amanady125@gmail.com)
>
> No Wine. No patching. 100% native Electron execution on Linux.

[![CI](https://github.com/AmanCode22/workbuddy-linux/actions/workflows/workbuddy-fedora.yml/badge.svg)](https://github.com/AmanCode22/workbuddy-linux/actions/workflows/workbuddy-fedora.yml)

## What is WorkBuddy?

WorkBuddy (workbuddy.ai / workbuddy.cn) is Tencent's AI office agent
workbench: chat with AI agents, delegate coding / document / browser /
terminal tasks, orchestrate multi-agent workflows, with WeChat & Tencent Docs
integration. Officially shipped for **Windows x64 and macOS only** — until
this port.

## How the port works (dissected from the official installers)

Both official installers were downloaded and dissected:

| Build | File | Format |
|---|---|---|
| Windows x64 | `WorkBuddy-win32-x64-user-…exe` (429 MB) | NSIS-3, electron-builder layout |
| macOS Intel | `WorkBuddy-darwin-x64-…zip` (504 MB) | standard Electron `.app` bundle |
| macOS ARM64 | `WorkBuddy-darwin-arm64-…dmg` (356 MB) | standard Electron `.app` bundle |

**Verdict: Electron 37.10.3 — NOT Tauri** (no WebView2, no Tauri artifacts;
`Electron Framework.framework`, `app.asar` 182 MB / 9,747 files, V8 snapshot,
chrome paks).

### The key discovery: the app is already Linux-ready inside

Tencent ships Linux support in every installer but never published it:

- `main/update-service.linux.js` + `main/appimage-self-update.js`
- `os-bridge.linux-x64-gnu-*.node`, `@lydell/node-pty-linux-x64/-arm64`
- koffi `prebuilds/linux-x64`
- Agent runtime downloads for Linux: Node (npmmirror), Python
  (python-build-standalone `x86_64-unknown-linux-gnu`)
- The app's own updater queries
  `https://www.workbuddy.ai/v2/update?platform=workbuddy-linux-x64-deb`
  — a **live official Linux update feed** (Tencent published official Linux
  DEB/RPM up to v5.5.2, then pulled the binaries; the feed metadata survives,
  the CDN objects are 404).

So the port is simply:

```
official darwin-x64 (Intel) app.asar + app.asar.unpacked
  + official Electron v37.10.3 linux-x64 runtime
  = native Linux WorkBuddy
```

The `darwin-x64` (Intel) channel is the source on purpose (see the update
API: `GET https://www.workbuddy.ai/v2/update?platform=workbuddy-darwin-x64`).
The asar JS is platform-neutral; all native modules ride along as Linux
prebuilds.

## Verified working

- Main process boots: AccountService, NetProxy, TencentDocs bridges registered
- UI renders under Xvfb (`screenshot-linux-port.png`)
- Daemon starts, `~/.workbuddy` state created
- Its Linux updater polls the official endpoint (HTTP 204 = up to date)

## Packages

| Package | Install |
|---|---|
| **DEB** (Debian/Ubuntu/Mint) | `sudo apt install ./workbuddyai-5.9.4-linux-amd64.deb` |
| **RPM** (Fedora/RHEL/openSUSE) | `sudo dnf install ./workbuddyai-5.9.4-1.x86_64.rpm` |
| **AppImage** (universal) | `chmod +x WorkBuddy-5.9.4-linux-x86_64.AppImage && ./WorkBuddy-5.9.4-linux-x86_64.AppImage` |
| **Flatpak** (sandboxed) | `flatpak install ./WorkBuddy-5.9.4-linux-x86_64.flatpak` |
| **Portable tarball** | `tar -xzf WorkBuddy-5.9.4-linux-x64-portable.tar.gz && "/opt/WorkBuddy AI/workbuddyai"` |

## CI (GitHub Actions)

`.github/workflows/workbuddy-fedora.yml` fully automates the port:

1. **resolve** — queries the official update API
   (`platform=workbuddy-darwin-x64`, Intel channel; ARM fallback)
2. **assemble** — downloads the official Intel ZIP, pairs the matching
   Electron linux-x64 runtime, assembles the app tree, **smoke-tests headless
   under Xvfb**
3. **package** — parallel jobs build DEB (dpkg-deb), RPM (rpmbuild),
   AppImage (appimagetool) and Flatpak (flatpak-builder, app-id
   `com.tencent.WorkBuddy`)
4. **release** — publishes all four packages + SHA256SUMS to a GitHub release

Run it manually via *Actions → WorkBuddy native Linux port → Run workflow*
(toggle `make_release` to publish), or wait for the nightly cron — whenever
Tencent ships a new version, a new Linux build rolls out on its own.

### Build locally

```bash
./scripts/assemble-app.sh --stage ./stage          # pulls latest from the update API
STAGE=$PWD/stage OUT=$PWD/dist VER=5.9.4 bash scripts/build-deb.sh
STAGE=$PWD/stage OUT=$PWD/dist VER=5.9.4 bash scripts/build-rpm.sh
STAGE=$PWD/stage OUT=$PWD/dist VER=5.9.4 bash scripts/build-appimage.sh
STAGE=$PWD/stage OUT=$PWD/dist VER=5.9.4 bash scripts/build-flatpak.sh
```

Requires: `7zz`, `jq`, `curl`, `dpkg-deb`, `rpmbuild`, `appimagetool`,
`flatpak-builder` (only for the format you want).

## Troubleshooting (Fedora / any Linux)

- **"Daemon service failed to start" dialog** — click Close and relaunch once
  (first-run runtime downloads).
- **No GPU?** Run with `--use-gl=swiftshader --enable-unsafe-swiftshader`.
- **Daemon can't find its managed runtime** — pre-provision:
  ```bash
  mkdir -p ~/.workbuddy/binaries/node/versions/22.22.2-6/bin \
           ~/.workbuddy/binaries/python/versions/3.13.12/bin
  ln -sf "$(command -v node)"   ~/.workbuddy/binaries/node/versions/22.22.2-6/bin/node
  ln -sf "$(command -v python3)" ~/.workbuddy/binaries/python/versions/3.13.12/bin/python3
  ```
- **Sandbox errors on some kernels** — AppImage/Flatpak wrappers pass
  `--no-sandbox` automatically; for DEB/RPM the chrome-sandbox is installed
  setuid root.
- macOS-only modules (WechatShare.appex, ImSDKForMac) are inert on Linux;
  WeChat/QQ sharing may be degraded.

## Credits & legal

- Port, packaging and CI by **AmanCode22**
  ([amanady125@gmail.com](mailto:amanady125@gmail.com))
- WorkBuddy and all app resources © Tencent Technology (Shenzhen) Company
  Limited. This project is **not affiliated with or endorsed by Tencent**.
  App resources are extracted from Tencent's own official installers at
  build time — verify `SHA256SUMS` against upstream. Use at your own risk.
- Update feed discovery: `GET /v2/update?platform=workbuddy-darwin-x64`
  (valid platforms: `workbuddy-darwin-x64`, `workbuddy-darwin-arm64`,
  `workbuddy-linux-x64-deb`, `workbuddy-linux-x64-rpm`,
  `workbuddy-linux-arm64-deb` — the Linux ones are metadata-only today).
