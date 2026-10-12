---
summary: How the two test suites (Swift Testing and Node) are wired, how they test the root script and the extension without touching the real system, and which test guards which cross-file invariant.
---

# Testing

## Purpose

The riskiest code here is code that can't be tried safely by hand. The root script rewrites the real `/etc/hosts` within a second, and the extension runs inside browsers. The tests check both without root, without a browser, and without changing anything outside a temp folder.

## Components

- `Tests/run.sh` — runs both suites. It's also the pre-commit hook (`.githooks/pre-commit`), enabled with `git config core.hooksPath .githooks`. Skip it once with `git commit --no-verify`.
- `Tests/DisciplinedTests/` — Swift Testing, the `DisciplinedTests` target in `project.yml`, run with `xcodebuild test`.
- `Tests/Extension/background.test.mjs` — Node's built-in `node:test`. It needs no packages.

## The Swift target

`DisciplinedTests` is a unit-test bundle that is **not hosted by the app**: launching the app would write the real blocklist. It compiles only `Domain.swift`, `BlockerHelper.swift` and `BrowserExtension.swift` alongside the tests. A test that needs another source file must add that file to the target in `project.yml`, then run `xcodegen generate`.

`Repo` (`Tests/DisciplinedTests/Repo.swift`) finds the repository root from `#filePath`. Tests use it to read the script, the manifests and `background.js` as they are on disk.

| Suite | What it checks |
| --- | --- |
| `DomainTests` | `Domain.normalize` on pasted URLs, rejection of anything that isn't a domain, and that a normalized domain normalizes to itself. The native host drops stored lines that don't. |
| `HelperScriptTests` | `apply-blocklist.sh` against a fake system: the hosts section, untrusted lines, turning off, extension vs. filter mode, `browsers.tsv` parsing and removal of stale policies. |
| `InvariantTests` | The cross-file invariants in [`CLAUDE.md`](../../CLAUDE.md#invariants-that-span-files), read from the actual files. |

### How `HelperScriptTests` fakes the system

`FakeSystem` builds a temp folder with `etc/hosts`, `Managed Preferences`, a state folder, a fake home with `Applications`, a blocklist and a dummy `.xpi`. Then it:

1. copies the script and rewrites four exact strings in it: `HOSTS="/etc/hosts"`, `MANAGED_PREFS="/Library/Managed Preferences"`, `STATE_DIR="/Library/Application Support/Disciplined"` and `for app in /Applications/*.app `. If any string isn't found, it throws `scriptChanged` instead of running a copy that would point at the real system;
2. puts stubs for `killall`, `dscacheutil` and `install` first on `PATH`. The `install` stub drops `-o`/`-g`, which need root;
3. builds fake Firefox-based apps with `makeGeckoApp`: an `Info.plist`, `.ini` files, and `omni.ja` archives whose `AppConstants.sys.mjs` sets `MOZ_REQUIRE_SIGNING`.

The suite runs serialized.

### Which test guards which invariant

| Invariant | Test |
| --- | --- |
| Domain regex identical in Swift, script and extension | `InvariantTests.domainPatternMatchesScriptAndExtension` |
| Host expansion matches the script's loop | `HelperScriptTests.blocksEachDomainAndKeepsTheRestOfHosts` |
| `browsers.tsv` format | `HelperScriptTests.forceInstallsExtensionOnlyWhereFirefoxAllowsIt` (the script writes it, `geckoBrowsers(in:)` parses it) |
| Chrome extension ID from `"key"` | `InvariantTests.chromeExtensionIDMatchesManifestKey` |
| Firefox extension ID in the manifest, Swift and the script | `InvariantTests.firefoxExtensionIDMatchesManifestAndScript` |
| `strict_min_version` equals `MIN_EXTENSION_GECKO` | `InvariantTests.minimumGeckoMatchesScript` |
| `.xpi` path and home folder derived from the blocklist path | `InvariantTests.scriptDerivesPathsFromBlocklistLocation` |
| The script treats the blocklist as untrusted | `HelperScriptTests.ignoresLinesThatArentDomains` |

When you add an invariant to `CLAUDE.md`, add a test for it and a row here.

## The extension tests

`background.test.mjs` runs `Extension/background.js` with `vm.runInNewContext`, using a fake `chrome` object that records:

- dynamic rules;
- tab redirects;
- `storage.local`;
- alarms;
- native connections.

It drives the script by calling the listeners the script registered, then waits one `setImmediate` so the promise chains finish. Values made inside the sandbox are passed through JSON before `deepEqual`, because their prototypes differ.

It covers matching subdomains but not lookalikes, the single rule with only valid domains, an empty list, tabs already open, blocking from saved rules after a restart, reconnecting, and the accent color validation.

## Known limitations

These are only checked by hand:

- the SwiftUI views and `BlockerModel`;
- the native host's stdio loop;
- `BrowserExtension.install()`;
- `BrowserRestarter`;
- `blocked.js`;
- the real launchd and osascript install.

## Related

- [root-helper.md](root-helper.md), [browser-extension.md](browser-extension.md).
