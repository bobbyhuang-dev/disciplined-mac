---
summary: How the app binary doubles as the browsers' native messaging host — launch detection, host manifests, the one-way message stream, and the heartbeat files the app reads as "connected".
---

# Native messaging host

## Purpose

The host gives the browser extension the current list and accent color without the app having to run. Browsers launch it while the extension is connected. It's the app's own executable, so there's no second binary to build, sign or install.

## Components

- `Sources/Entry.swift` — `Entry.main()` runs `NativeHost.run(for:)` instead of the UI when `NativeHost.launchingBrowser` isn't nil.
- `Sources/NativeHost.swift` — launch detection and the message loop.
- `Sources/BrowserExtension.swift` — `writeHostManifests(gecko:)`, `markConnected(_:)`, `isConnected(_:)`.

## Launch detection

`NativeHost.launchingBrowser` looks at the launch arguments:

- If an argument starts with `chrome-extension://`, the browser is Chromium, and the heartbeat key is `chrome`.
- If an argument equals `disciplined@disciplined.mac`, the browser is Firefox-based. The key is the bundle ID of the `.app` that contains the parent process (Firefox launches hosts from its main process), or `firefox` if that can't be found.
- Otherwise it's a normal app launch.

## Host manifests

The manifest file is `com.disciplined.mac.json` with `type: stdio`, and its `path` is `Bundle.main.executablePath`. So the manifests follow whichever copy of the app ran last, including one in `build/`. The Chromium manifest allows `chrome-extension://<extensionID>/`, and the Firefox one allows `disciplined@disciplined.mac`.

It goes in `NativeMessagingHosts/` inside each of these folders under `~/Library/Application Support/`, but only where that folder already exists, meaning the browser is installed:

- Chromium: `Google/Chrome`, `BraveSoftware/Brave-Browser`, `Microsoft Edge`, `Chromium`, `Vivaldi`.
- Firefox-based: `Mozilla`, plus each detected browser's profile folder from `browsers.tsv`. Forks that moved their data folder read host manifests from there.

A file is rewritten only when its content changes. The manifests are written at app launch, and again whenever `BlockerModel.refresh()` sees the list of Firefox-based browsers change.

## Message loop

`NativeHost.run(for:)` never returns:

- A background thread reads stdin until it closes, then exits. The browser closes stdin when the extension disconnects. The host never reads or answers messages from the extension.
- The main loop runs once a second:
  1. It reads `blocklist.txt` and keeps only the lines where `Domain.normalize(line) == line`.
  2. It sends `{"domains": [...]}` if the list differs from the last one sent.
  3. It sends `{"accent": {"light", "dark"}}` from `AppTheme.savedColors` if those differ.
  4. It touches the heartbeat file.

  The first pass always sends both.
- Each message is a 32-bit native-endian length followed by UTF-8 JSON.

The host only reads files. That's why the extension stays current while the app's window or process is closed. It's also why the accent color comes from the saved `appThemeColors` rather than being resolved here (see [accent-color.md](accent-color.md)).

## Heartbeats

`markConnected(key)` writes an empty file at `~/Library/Caches/com.disciplined.mac/extension-heartbeat-<key>`. `isConnected(key)` is true while that file was modified less than 3 seconds ago. The app polls it to show each browser as connected.

## Known limitations

- Every Chromium browser shares the `chrome` key, so the app can't tell which Chromium browser is connected.
- If the parent's bundle ID can't be found, the key is `firefox`. That matches no row in `browsers.tsv`, so the browser won't show as connected.
- Running a build from anywhere other than `/Applications` re-points the manifests at that copy until the `/Applications` copy runs again.

## Related

- [browser-extension.md](browser-extension.md): what the extension does with these messages.
- [app-state.md](app-state.md): how heartbeats feed the "needs restart" logic.
