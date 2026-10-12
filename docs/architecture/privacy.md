---
summary: How site names are kept out of sight — the hidden site list with optional Touch ID, the anonymous blocked page, hashed favicon caching — and the rules new code must follow.
---

# Privacy

## Purpose

A blocklist says a lot about the person who wrote it. Site names must never be visible by default: not on screen, in a screen share, in a window or tab title, or in a file name or cache.

## Components

- `Sources/SiteListPrivacy.swift` — the settings keys, `authenticate()` and `hideTriggers`.
- `Sources/ContentView.swift` — `MainView` (the `revealed` state) and `HiddenList`.
- `Sources/Favicon.swift` — fetching and caching site icons.
- `Extension/blocked.html`, `Extension/blocked.js` — the anonymous blocked page.

## The site list

- With `hideSiteList` on, which is the default, the main window shows "N sites hidden" and a **Show Sites** button instead of the list. A footer button toggles it again.
- With `authenticateToShowSites` on (off by default), Show Sites first asks for Touch ID, or the login password on Macs without it, through `LAContext` and `.deviceOwnerAuthentication`. If the Mac has no way to authenticate, the list is shown anyway, so the user is never locked out of their own list.
- `revealed` is view state that is never saved. The window always opens hidden. It hides again when the window disappears, and on any of `SiteListPrivacy.hideTriggers`:
  - the app resigning active;
  - the Mac going to sleep;
  - the screens going to sleep;
  - fast user switching;
  - `com.apple.screenIsLocked`.
- Adding a site still works while the list is hidden. The field clears and briefly confirms the addition instead of showing the new row.

## The blocked page

It never names the site. The redirect rule sends every blocked site to the same `/blocked.html`, with no query string, and the page title is a generic "Blocked". Nothing site-specific reaches the address bar, the tab title, history or a screen share. See [browser-extension.md](browser-extension.md#the-blocked-page).

## Site icons

- A blocked site resolves to `0.0.0.0`, so its icon can't come from the site itself. It comes from a favicon service chosen in Settings: Google (the default) or DuckDuckGo. Showing icons is the `showSiteIcons` setting, on by default.
- Icons are cached under `~/Library/Caches/com.disciplined.mac/SiteIcons/<source>/<sha256 of domain>`, so the folder doesn't spell out the list.
- Requests go through an ephemeral `URLSession`, so they aren't stored in the shared `Cache.db`.
- At launch, `Favicon.removeLegacyCaches()` deletes caches left by older builds: a `Favicons` folder named after each site, and the shared URL cache.
- Lookups the service had no icon for are remembered in memory until the next launch.

## Rules for new code

- Don't put site names in window or page titles, notifications, logs, URLs or query strings, file names, or anything shown before the user asks to see the list.
- Cache or store anything per-site under a hash, not the domain.
- Docs and examples use `example.com`, `example.org` or `example.net` (see [`docs/README.md`](../README.md#privacy)).

## Known limitations

- With site icons on, the chosen favicon service receives every domain on the list. It also receives whatever is typed into the add field, looked up after a 350 ms pause. Turning the setting off stops these requests.
- `blocklist.txt`, `/etc/hosts` and the Firefox policy files contain the domains in plain text. They have to, because the system and the browsers read them.

## Related

- [overview.md](overview.md#files-on-disk) lists every file the app writes.
