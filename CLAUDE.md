# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Disciplined is a macOS 14+ SwiftUI app (Swift 6 language mode, so strict concurrency) that blocks websites system-wide and in browsers. The repo has no linter or package dependencies. Tests are described under Testing.

Deeper docs live in `docs/`: architecture, decisions (the reasons behind choices) and guides. Check the indexes there before changing a subsystem. Follow the rules in `docs/README.md` when adding or editing docs, and update any doc a code change makes wrong in the same change.

## Commands

```bash
# Build (the output goes to ./build, which is gitignored)
xcodebuild -project Disciplined.xcodeproj -scheme Disciplined -configuration Debug -derivedDataPath build build

# Install the fresh build to /Applications and relaunch it from there (see "Development gotchas").
# The native messaging host uses the same binary name, so don't `killall Disciplined`.
osascript -e 'quit app "Disciplined"'; rsync -a --delete build/Build/Products/Debug/Disciplined.app/ /Applications/Disciplined.app/ && open /Applications/Disciplined.app

# Run every test (also runs as the pre-commit hook in .githooks; enable it with `git config core.hooksPath .githooks`)
Tests/run.sh

# Regenerate the Xcode project after adding/removing files or changing settings (project.yml is the source of truth)
xcodegen generate
```

## Architecture

Full detail is in `docs/architecture/`; start with `overview.md`, which also lists every shared file and defaults key.

There are three enforcement layers. They all read one user-owned file: `~/Library/Application Support/Disciplined/blocklist.txt`, with one domain per line. `BlockerModel.persist()` writes the list there, and writes an empty file when blocking is off. The UserDefaults `domains` and `isBlocking` are the source of truth.

1. **Root helper** (`root-helper.md`). This is a LaunchDaemon, installed once with an admin password, that runs `Resources/apply-blocklist.sh` as root whenever the blocklist changes. It rewrites a marked section of `/etc/hosts` and writes managed policies for Firefox-based browsers: **extension** mode force-installs the `.xpi`, and **filter** mode uses `WebsiteFilter`, read only at startup.
2. **Browser extension** (`browser-extension.md`). `Extension/` is the Chromium MV3 build, loaded unpacked by the user. The app also turns it into a Firefox MV2 `.xpi`. It uses one dynamic `declarativeNetRequest` redirect rule to `blocked.html`, and also checks open tabs.
3. **Native messaging host** (`native-messaging-host.md`). The app binary doubles as the host (`Entry.swift`). It streams the list and the accent color to the extension, and touches a heartbeat file the app reads as "connected".

`BlockerModel` (`app-state.md`) polls once per second to derive the status and each browser's "needs restart".

## Testing

`Tests/run.sh` runs both suites: Swift Testing in `Tests/DisciplinedTests`, and Node's `node:test` in `Tests/Extension`. Run it after every change, and add a test when you change something they cover. How the suites work, and which test guards which invariant, is in `docs/architecture/testing.md`.

- The Swift test target isn't hosted by the app, because launching the app writes the real blocklist. It compiles only `Domain.swift`, `BlockerHelper.swift` and `BrowserExtension.swift`. If a test needs another file, add it to `project.yml`.
- `HelperScriptTests` rewrites exact lines of `apply-blocklist.sh` to point it at a fake system. If you change those lines, update the test.

## Accent color

Never hard-code the app's color. Use `.tint` as a shape style, or `theme.color` when you need a gradient. The color reaches the blocked page through `appThemeColors` and the native host. See `docs/architecture/accent-color.md`.

## Privacy

Site names are sensitive, so keep them out of anything visible by default: titles, notifications, logs, URLs and file names. Hash anything you store per site. The site list hides behind "Show Sites", and the blocked page never names the site. See `docs/architecture/privacy.md`.

## Localization

English is the source language; Simplified Chinese is the only translation. See `docs/architecture/localization.md`.

- Strings built in code use `String(localized:)`, and so do ternaries of literals. SwiftUI literals are localized automatically.
- `xcodebuild` doesn't sync `Resources/Localizable.xcstrings`, so add new keys by hand. Interpolations become `%@` (strings) and `%lld` (integers).
- Extension strings live in `Extension/_locales/{en,zh_CN}/messages.json`.

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
- **Run the app from `/Applications`.** On macOS 27, System Settings → Menu Bar → "Allow in the Menu Bar" only reaches a status item when the app runs from `/Applications`. Run from `build/`, `~/Applications` or anywhere else, `MenuBarAgent` can't tie the item to the bundle, so it always shows. Signing, SwiftUI vs. AppKit and the debug dylib make no difference. Its `statusItems` log category prints `No server elements for status item: nil` when this happens.
