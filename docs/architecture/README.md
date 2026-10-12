# Architecture

Each doc here describes how one subsystem works today: which pieces are involved, how data and control move between them, and what must stay true across files. They describe the current state in the present tense. When the code changes, the doc changes with it.

Reasons belong in [`decisions/`](../decisions/README.md). Link to the relevant decision instead of re-arguing it here. The one-paragraph overview of the whole app lives in [`CLAUDE.md`](../../CLAUDE.md#architecture). Docs here go deeper on one part.

Start from [`templates/architecture.md`](../templates/architecture.md). The rules are in [`docs/README.md`](../README.md).

## Index

<!-- One line per doc, alphabetical after the overview: - [Title](file.md) — summary from its front matter -->

Start with the overview, which maps the processes and every shared file.

- [Overview](overview.md) — Map of the whole system — the four processes, how the blocklist flows between them, and every file and defaults key they share.
- [Accent color](accent-color.md) — How the accent color chosen in Settings tints the app and reaches the extension's blocked page through appThemeColors, the native host and storage.local.
- [App state and status](app-state.md) — How BlockerModel stores the list, writes it out, polls the applied state every second, derives the status, and decides when a Firefox-based browser needs a restart (and how BrowserRestarter does it).
- [Browser extension](browser-extension.md) — How the one extension source becomes a Chromium MV3 folder and a Firefox MV2 .xpi, how background.js turns the list into a single redirect rule and checks open tabs, and how the blocked page works.
- [Localization](localization.md) — How the app (String Catalog) and the extension (_locales) are localized into English and Simplified Chinese, how the in-app language picker works, and where new strings and languages go.
- [Native messaging host](native-messaging-host.md) — How the app binary doubles as the browsers' native messaging host — launch detection, host manifests, the one-way message stream, and the heartbeat files the app reads as "connected".
- [Privacy](privacy.md) — How site names are kept out of sight — the hidden site list with optional Touch ID, the anonymous blocked page, hashed favicon caching — and the rules new code must follow.
- [Root helper](root-helper.md) — How the root LaunchDaemon is installed and removed, and what apply-blocklist.sh does on each run to /etc/hosts, Firefox-based browsers' policies and browsers.tsv.
- [Testing](testing.md) — How the two test suites (Swift Testing and Node) are wired, how they test the root script and the extension without touching the real system, and which test guards which cross-file invariant.
