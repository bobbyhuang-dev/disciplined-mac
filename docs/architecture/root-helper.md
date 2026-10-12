---
summary: How the root LaunchDaemon is installed and removed, and what apply-blocklist.sh does on each run to /etc/hosts, Firefox-based browsers' policies and browsers.tsv.
---

# Root helper

## Purpose

This is the only part that runs as root. It blocks sites system-wide through `/etc/hosts`, and in Firefox-based browsers through managed policies, which still apply when a proxy or DNS-over-HTTPS skips the hosts file. It's installed once with an admin password and then runs on its own whenever the blocklist file changes.

## Components

- `Sources/BlockerHelper.swift` — `BlockerHelper`: paths, install and uninstall, `isInstalled`, `appliedHosts()`, `writeBlocklist(_:)`.
- `Resources/apply-blocklist.sh` — the script launchd runs. Usage: `apply-blocklist.sh <path-to-blocklist>`.
- `/Library/LaunchDaemons/com.disciplined.blocker.plist` — the daemon, which the app generates at install time.

## Install and uninstall

`BlockerHelper.install()` creates an empty `blocklist.txt` if there isn't one yet, writes the daemon plist to a temp folder, then runs one shell script through `osascript … with administrator privileges`. That's the app's only password prompt. The script:

1. creates `/Library/Application Support/Disciplined/`;
2. installs `apply-blocklist.sh` there as `root:wheel 755`;
3. boots out any existing daemon, installs the plist as `root:wheel 644` and bootstraps it.

The daemon plist:

| Key | Value | Why |
| --- | --- | --- |
| `ProgramArguments` | `/bin/bash <script> <blocklist path>` | The user's blocklist path is fixed at install time. |
| `WatchPaths` | The blocklist file and its folder | Atomic saves replace the file, and only the folder sees that. |
| `RunAtLoad` | `true` | Applies the list at boot. |
| `StartInterval` | `60` | Re-applies regularly, so a deleted policy file comes back. |
| `ThrottleInterval` | `1` | Lets edits apply within about a second. |

`BlockerHelper.uninstall()` ("Remove Blocker Helper…" in the app menu) boots out the daemon, deletes the plist, and runs the installed script once with an empty list path. That removes the hosts section and every policy the script wrote. Then it deletes the helper folder.

Cancelling the password dialog makes osascript fail with `-128`. That error becomes `HelperError.cancelled`, which `BlockerModel` ignores without showing anything.

### `isInstalled`

`BlockerHelper.isInstalled` is true only when the daemon plist exists and the installed script is byte-for-byte the same as the bundled one. So any edit to the script makes the app ask for setup again (see the gotcha in [`CLAUDE.md`](../../CLAUDE.md#development-gotchas)). The `# helper-version:` comment, currently 7, is bumped on every script change so the two copies always differ.

## What one run of the script does

1. **Copies `/etc/hosts` without its old section**, using `awk` between the begin and end marks.
2. **Reads the list strictly:** it strips `\r`, keeps only lines matching `DOMAIN_RE`, takes at most 5000 and removes duplicates. Lines aren't lowercased: an uppercase line is dropped. The app only ever writes normalized, lowercase domains.
3. **Appends a new section** if any domains are left. For each domain `d`, it adds `d`, `www.d` and `m.d`, each as `0.0.0.0 host` and `:: host`.
4. **Writes `/etc/hosts` only if it changed**, in place (`cat >`, keeping the file's owner and mode). Then it flushes `dscacheutil` and sends `HUP` to `mDNSResponder`.
5. **Builds two policy bodies:**
   - **filter:** `WebsiteFilter.Block` with `*://*.d/*` for each domain (this pattern also matches `d` itself). It's built whenever a list path is given, even when the list is empty. An empty policy still gets a new modification date, and the app uses that date to ask for a browser restart after blocking is turned off.
   - **extension:** `ExtensionSettings` force-installs `disciplined@disciplined.mac` from a `file://` URL to the `.xpi` beside the blocklist, and locks `xpinstall.signatures.required` to false. It's only built if that `.xpi` exists and its path contains none of `<>&"'%#?`, which would need escaping.
6. **Detects Firefox-based browsers** in `/Applications/*.app` and `~/Applications/*.app`. It finds the home folder by stripping `/Library/Application Support/Disciplined/blocklist.txt` from the list path. An app counts as Firefox-based if it has `Contents/Resources/omni.ja`, `browser/omni.ja` and `application.ini`. For each one:
   - the bundle ID comes from `Info.plist` and must match `BUNDLE_ID_RE`;
   - the profile folder is `Profile=` (or `Name=`) from `application.ini`, and must contain no `/` or tab;
   - the mode is **extension** only if the extension body exists, `Milestone` in `platform.ini` is at least `MIN_EXTENSION_GECKO` (128), and `modules/AppConstants.sys.mjs` inside `omni.ja` contains `MOZ_REQUIRE_SIGNING: false`. Otherwise it's **filter**.
7. **Writes each browser's policy** to `/Library/Managed Preferences/<bundle-id>.plist`. The XML is assembled with `printf`, checked with `plutil -convert xml1`, and installed only if it changed. The script writes the file directly because cfprefsd treats that folder as read-only, so `defaults` can't write there.
8. **Removes stale policies.** These belong to bundle IDs in the previous `browsers.tsv` that are no longer installed, plus `OLD_FIREFOX_IDS` and `OLD_CHROMIUM_IDS`, which earlier helper versions wrote.
9. **Writes `browsers.tsv`** if it changed. Its line format is listed in [`CLAUDE.md`](../../CLAUDE.md#invariants-that-span-files).
10. **Kills `cfprefsd`** if any policy changed. It caches managed preferences and never notices the files changing, and launchd restarts it on demand.

### The two browser modes

| | extension | filter |
| --- | --- | --- |
| Which browsers | Built without mandatory signing, Gecko ≥ 128 (for example Zen, LibreWolf, Developer Edition, Nightly, ESR) | Release Firefox, and anything older or unrecognized |
| List updates | Live, through the [native host](native-messaging-host.md) | Only when the browser starts |
| Blocked page | The extension's `blocked.html`, in the accent color | Firefox's own error page |
| Restart needed | After the `.xpi` or the policy changes, or if the extension never connects | After every list change |

## Invariants

- The script treats `blocklist.txt` as untrusted input: it's user-writable, and the script runs as root. Every value that reaches a file or a command (domains, bundle IDs, profile names, app paths, the `.xpi` path) is validated or escaped first. Keep it that way.
- `DOMAIN_RE`, the host expansion loop, `EXTENSION_ID`, `MIN_EXTENSION_GECKO`, the `browsers.tsv` format and the `.xpi` path are shared with other files. They're listed in [`CLAUDE.md`](../../CLAUDE.md#invariants-that-span-files) and checked by the tests.
- `HelperScriptTests` rewrites four exact lines of the script to point it at a fake system (see [testing.md](testing.md)). Changing those lines means updating the test.

## Known limitations

- `/etc/hosts` only covers `d`, `www.d` and `m.d`. Other subdomains, such as `mail.example.com`, are blocked only by the extension or the filter policy, which match every subdomain.
- Chromium browsers get no policy. They're covered by the hosts file and by the extension, which the user loads by hand.
- The helper only scans `/Applications` and `~/Applications`, so a Firefox-based browser installed anywhere else gets no policy.
- The daemon has no log. To see what it applied, see [`CLAUDE.md`](../../CLAUDE.md#development-gotchas).

## Related

- [app-state.md](app-state.md): how the app reads back this state and decides "Applying…" or "needs restart".
- [browser-extension.md](browser-extension.md): the `.xpi` this helper force-installs.
