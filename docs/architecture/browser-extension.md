---
summary: How the one extension source becomes a Chromium MV3 folder and a Firefox MV2 .xpi, how background.js turns the list into a single redirect rule and checks open tabs, and how the blocked page works.
---

# Browser extension

## Purpose

The extension blocks inside the browser, so it works even when a proxy, VPN or DNS-over-HTTPS skips `/etc/hosts`. It gets the list from the [native host](native-messaging-host.md), and it keeps blocking with its last list when the host can't run.

## Components

- `Extension/manifest.json` — Chromium, Manifest V3.
- `FirefoxExtension/manifest.json` — Firefox-based browsers, Manifest V2. It's the only file that differs between the two builds.
- `Extension/background.js` — all of the logic, shared by both builds through `globalThis.browser ?? chrome`.
- `Extension/blocked.html`, `blocked.css`, `blocked.js` — the page that blocked sites redirect to.
- `Extension/_locales/{en,zh_CN}/messages.json` — strings (see [localization.md](localization.md)).
- `Sources/BrowserExtension.swift` — `BrowserExtension.install()` copies and packages the extension. It also writes the host manifests and reads heartbeats.

## Packaging

`BrowserExtension.install()` runs on every app launch, from `BlockerModel.init()`.

- **Chromium.** The bundled `Extension/` is mirrored to `~/Library/Application Support/Disciplined/Chrome Extension/`, but only if any file differs. The user loads that folder unpacked. It sits outside the app bundle, so it survives the app being moved. The extension ID, `BrowserExtension.extensionID`, is fixed by `"key"` in the manifest. The main window's footer suggests the first installed browser among Chrome, Brave, Edge, Chromium and Vivaldi (`BrowserExtension.chromiumBrowser`).
- **Firefox-based browsers.** `Extension/` is copied to a temp folder, its manifest is replaced with `FirefoxExtension/manifest.json`, and the result is mirrored to `…/Disciplined/Firefox Extension/`. Only when that mirror changed, or the `.xpi` is missing, is it zipped (`zip -q -X -r`) into a temp file and swapped into `…/Disciplined/Disciplined.xpi`. The [root helper](root-helper.md) force-installs it from there in extension-mode browsers. The browser reinstalls it at every launch.

### Manifest differences

| | `Extension/manifest.json` | `FirefoxExtension/manifest.json` |
| --- | --- | --- |
| Version | MV3 | MV2 |
| Background | `service_worker` | `scripts` |
| `<all_urls>` | `host_permissions` | in `permissions` |
| `action` | Empty, with icons only: without it, Chrome grays out the toolbar icon on pages the extension can't access, such as `blocked.html` | None |
| ID | From `"key"` | `browser_specific_settings.gecko.id`, with `strict_min_version` `128.0` |

## How `background.js` works

- **On load:** it reads the dynamic rules it saved earlier and rebuilds `blocked` from their `requestDomains`. This `ready` promise is awaited before any check, so a restarted service worker blocks correctly before the host has sent anything. Then it calls `connect()`.
- **`{domains: [...]}` from the host:** the extension keeps only strings that match `DOMAIN_RE` and removes duplicates. It then replaces all dynamic rules with a single rule, `id: 1`, which redirects `main_frame` and `sub_frame` requests for those `requestDomains` (which include subdomains) to `/blocked.html`. An empty list removes the rule. Finally, it checks every open tab.
- **Tab checks:** `tabs.onUpdated` with a URL redirects the tab if its hostname equals a listed domain or ends with `.domain`. Rules only catch new requests, so this covers tabs opened before the list arrived and in-page navigation.
- **`{accent: {light, dark}}` from the host:** the colors are saved to `storage.local` only if both are lowercase `#rrggbb` (see [accent-color.md](accent-color.md)).
- **Disconnect:** the reason is logged, and a `reconnect` alarm is set for 30 seconds later. When it fires, the extension reconnects if it has no open port. An open native messaging port also keeps the MV3 service worker alive. The empty `runtime.onStartup` listener exists only to wake the worker when the browser starts.

Dynamic rules persist across browser restarts. If the host can't launch at all, for example because the app was deleted, the extension keeps blocking with the last list it got.

## The blocked page

- It never names the site. There's no query string, and the title is a generic "Blocked", because the title shows in the tab bar, window lists and screen shares. See [privacy.md](privacy.md).
- Its text comes from `_locales` through `i18n.getMessage`. If that returns an empty string (an unpacked extension whose files changed without a reload), it falls back to the English text already in the HTML.
- The `<main>` content stays transparent (`.loading`) until the accent color is read from storage, so it doesn't flash the default indigo. It also follows `storage.onChanged`.
- The shield is the app icon's shield path with the dot cut out.

## Invariants

- `DOMAIN_RE` must match `Domain.pattern` and the script's. The extension ID and the Firefox ID are fixed. See [`CLAUDE.md`](../../CLAUDE.md#invariants-that-span-files).
- Any code that needs the browser API goes through `api`, never `chrome` or `browser` directly, so it works in both builds.

## Known limitations

- Chromium users have to load the extension by hand at `chrome://extensions`, and reload it there after it changes. How changes reach each kind of browser is in [`CLAUDE.md`](../../CLAUDE.md#development-gotchas).
- Filter-mode Firefox doesn't run the extension at all.

## Related

- [native-messaging-host.md](native-messaging-host.md): the other end of the port.
- `Tests/Extension/background.test.mjs` ([testing.md](testing.md)).
