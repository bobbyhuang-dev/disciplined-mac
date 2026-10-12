---
summary: How BlockerModel stores the list, writes it out, polls the applied state every second, derives the status, and decides when a Firefox-based browser needs a restart (and how BrowserRestarter does it).
---

# App state and status

## Purpose

`BlockerModel` is the app's single source of state. It owns the list and the toggle, writes them where the other parts read them, and turns what those parts report back into the status the UI shows.

## Components

- `Sources/BlockerModel.swift` — `BlockerModel` (`@MainActor @Observable`), `GeckoBrowserStatus`.
- `Sources/Domain.swift` — `Domain.normalize(_:)` and `Domain.hosts(for:)`.
- `Sources/BrowserRestarter.swift` — `BrowserRestarter.restart(_:)`.
- `Sources/DisciplinedApp.swift` — creates the one model and passes it to the window and the menu bar item.

## Storing and writing the list

- `domains` (newest first) and `isBlocking` are saved in UserDefaults. These are the source of truth.
- `add(_:)` runs the input through `Domain.normalize`, which reduces a pasted URL to a lowercase bare domain without `www.`. It returns false for invalid input and ignores duplicates.
- `persist()` runs after every edit and toggle, at launch, and after the helper is installed or removed. It saves both defaults, then calls `BlockerHelper.writeBlocklist`, which writes the domains while blocking is on and an empty file while it's off. Then it calls `refresh()`.

## Polling

`startMonitoring()` calls `refresh()` once a second. Each pass:

1. reads `BlockerHelper.isInstalled`, `BlockerHelper.appliedHosts()`, the Chromium heartbeat and `browsers.tsv`;
2. rewrites the host manifests if the set of Firefox-based browsers changed;
3. computes a `GeckoBrowserStatus` for each browser;
4. calls `AppTheme.saveColors()`;
5. assigns each property only if it changed, so the poll doesn't redraw the UI every second.

## Status

`status` is checked in this order:

| Status | When | Shown as |
| --- | --- | --- |
| `needsSetup` | The helper isn't installed, or its script differs from the bundled one | The setup screen; "Setup needed" |
| `applying` | The hosts in `/etc/hosts` differ from `Domain.hosts(for:)` over the list (or from nothing, while off) | "Applying…" |
| `active` | Blocking is on and the list isn't empty | "Blocking N sites", and a filled menu bar icon |
| `off` | Otherwise | "Off" |

Because `applying` compares the exact set of hosts, the status sticks on "Applying…" if `Domain.hosts(for:)` and the script's host loop ever differ.

## Firefox-based browsers: connected and needs restart

For each browser in `browsers.tsv`, `BlockerModel.status(of:)` works out:

- `connected`: its heartbeat (keyed by bundle ID) is fresh.
- `isRunning`: it has a running instance. The launch date used below is the earliest one among its instances.
- `needsRestart`, only while it's running. Here, "changed" means its policy plist or `Disciplined.xpi` was modified after that launch:
  - in **extension** mode: it isn't connected, and either something changed or it has been running for more than 15 seconds. Once connected, list changes arrive live, so a restart isn't needed.
  - in **filter** mode: something changed. The policy is the list, and it's only read at startup.

## Restarting a browser

`BrowserRestarter.restart(_:)`, started from a browser's row in the footer:

1. **Finds the profiles in use:** those listed in `profiles.ini` whose `.parentlock` is locked, checked with `fcntl(F_GETLK)` without taking the lock. If none are locked, it falls back to the `Default=` profiles in `installs.ini`.
2. **Quits every instance** and waits up to 30 seconds. After that, it throws `didNotQuit`; the usual cause is an open dialog.
3. **Appends `browser.sessionstore.resume_session_once = true`** to each profile's `prefs.js`. This must happen after the browser exits, because the browser rewrites `prefs.js` on quit.
4. **Reopens the app.** It restores the windows and tabs once, whatever the user's startup setting is.

## Errors

Errors from installing, the extension or restarts land in `errorMessage`, which the main window shows under the list. If the user cancels the password dialog, no error is shown.

## Related

- [root-helper.md](root-helper.md) writes what the poll reads back.
- [native-messaging-host.md](native-messaging-host.md) writes the heartbeats.
- [overview.md](overview.md) lists every file and defaults key.
