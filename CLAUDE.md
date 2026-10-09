# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Disciplined is a macOS 14+ SwiftUI app (Swift 6 language mode, so strict concurrency) that blocks websites system-wide and in browsers. The repo has no tests, linter or package dependencies.

## Commands

```bash
# Build (the output goes to ./build, which is gitignored)
xcodebuild -project Disciplined.xcodeproj -scheme Disciplined -configuration Debug -derivedDataPath build build

# Relaunch the fresh build. The native messaging host uses the same binary name, so don't `killall Disciplined`.
osascript -e 'quit app "Disciplined"'; open build/Build/Products/Debug/Disciplined.app

# Regenerate the Xcode project after adding/removing files or changing settings (project.yml is the source of truth)
xcodegen generate
```

## Architecture

There are three enforcement layers. They all read one user-owned file: `~/Library/Application Support/Disciplined/blocklist.txt`, with one domain per line. `BlockerModel.persist()` writes the list there, and writes an empty file when blocking is off.

1. **Root helper (`/etc/hosts` + Firefox policies).** `BlockerHelper.install()` uses `osascript … with administrator privileges` (the only password prompt) to install `Resources/apply-blocklist.sh` to `/Library/Application Support/Disciplined/` and a LaunchDaemon `com.disciplined.blocker`. launchd's `WatchPaths` on the blocklist file *and its folder* (atomic saves replace the file) run the script as root on every change, and every 60s. The script:
   - rewrites the marked section of `/etc/hosts` (`domain`, `www.`, `m.` for each domain, as both `0.0.0.0` and `::`)
   - detects Firefox-based browsers in `/Applications` and `~/Applications`, then writes `/Library/Managed Preferences/<bundle-id>.plist` for each. The **extension** mode force-installs the unsigned `.xpi`; it's used where the browser allows unsigned add-ons and has Gecko ≥ 128. The **filter** mode uses a `WebsiteFilter` policy; release Firefox gets this, and it only applies at browser startup.
   - records what it found in `/Library/Application Support/Disciplined/browsers.tsv`, which the app reads.
2. **Browser extension (`Extension/`).** It uses dynamic `declarativeNetRequest` redirect rules to `blocked.html`, and also checks open tabs. Chromium gets this folder as-is (MV3). The user loads it unpacked from `~/Library/Application Support/Disciplined/Chrome Extension`. `BrowserExtension.install()` mirrors it there on every app launch. For Firefox, the app copies `Extension/`, swaps in `FirefoxExtension/manifest.json` (MV2), and zips the result to `Disciplined.xpi` beside the blocklist. `background.js` is shared by both builds through `globalThis.browser ?? chrome`.
3. **Native messaging host.** The app binary doubles as the host. In `Entry.swift`, if the launch args contain a `chrome-extension://` origin or the Firefox extension ID, it runs `NativeHost.run` instead of the UI. That loop streams `{domains: [...]}` from blocklist.txt every second and touches a heartbeat file at `~/Library/Caches/com.disciplined.mac/extension-heartbeat-<key>`. The key is `chrome` or the Gecko browser's bundle ID. A heartbeat newer than 3s counts as "connected". The host manifests point at `Bundle.main.executablePath`, so they follow whichever copy of the app ran last.

`BlockerModel` (`@MainActor @Observable`) polls once per second (`refresh()`): helper installed, hosts applied, heartbeats, `browsers.tsv`, and per-browser "needs restart". It compares policy and `.xpi` modification dates against the browser's launch date to decide on a restart. To avoid redraws, it only assigns properties that changed. The status shows "Applying…" while the hosts in `/etc/hosts` differ from `Domain.hosts(for:)` over the list. `BrowserRestarter` quits a Gecko browser and reopens it with its session restored.

## Invariants that span files

- **Domain regex.** `Domain.pattern` (Swift), `DOMAIN_RE` in `apply-blocklist.sh`, and `DOMAIN_RE` in `Extension/background.js` must stay identical.
- **Host expansion.** `Domain.hosts(for:)` must match the `for h in …` loop in the script, or the status sticks on "Applying…".
- **`browsers.tsv` format.** Each line is `bundle-id<TAB>mode<TAB>profile-folder<TAB>app-path`. The script writes it and `BrowserExtension.geckoBrowsers()` parses it.
- **Fixed IDs and paths.**
  - The Chrome extension ID comes from `"key"` in `Extension/manifest.json`.
  - The Firefox ID `disciplined@disciplined.mac` appears in `FirefoxExtension/manifest.json`, `BrowserExtension.firefoxExtensionID` and `EXTENSION_ID` in the script.
  - `strict_min_version` 128 matches `MIN_EXTENSION_GECKO`.
  - The `.xpi` path that the script derives from the blocklist's folder must equal `BrowserExtension.xpiURL`.
- **The script treats the blocklist as untrusted input** (it's user-writable and the script runs as root), so keep its strict validation and escaping.

## Development gotchas

- **Any edit to `apply-blocklist.sh` un-installs the helper as far as the app knows.** `BlockerHelper.isInstalled` compares the installed script byte-for-byte with the bundled one. After a rebuild, the app shows the setup screen until the user clicks Continue and enters their admin password, which Claude can't do, so tell the user. Bump the `# helper-version:` comment when changing the script.
- **The helper is live on the dev machine.** Writing `blocklist.txt` changes the real `/etc/hosts` and browser policies within about a second. If a test touches it, back it up first and restore it with a trap.
- Extension changes reach browsers in different ways:
  - Chromium needs a reload at `chrome://extensions`.
  - Gecko browsers in extension mode need a restart, because the `.xpi` is reinstalled at startup.
  - Filter-mode browsers only pick up list changes on restart.
- To inspect applied state without root, read the `# >>> Disciplined blocklist >>>` section of `/etc/hosts`, `/Library/Managed Preferences/<bundle-id>.plist` and `/Library/Application Support/Disciplined/browsers.tsv`. The daemon has no log file.
