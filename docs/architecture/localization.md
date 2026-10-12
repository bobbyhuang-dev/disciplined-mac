---
summary: How the app (String Catalog) and the extension (_locales) are localized into English and Simplified Chinese, how the in-app language picker works, and where new strings and languages go.
---

# Localization

## Purpose

The app and the extension are translated. English is the source language, and Simplified Chinese is the only translation.

## Components

- `Resources/Localizable.xcstrings` — the app's String Catalog.
- `Extension/_locales/{en,zh_CN}/messages.json` — the extension's strings, read by `blocked.js` and by the manifests' `__MSG_…__` placeholders.
- `Sources/AppLanguage.swift` — the language picker in Settings → Language.
- `project.yml` — `SWIFT_EMIT_LOC_STRINGS` and `LOCALIZATION_PREFERS_STRING_CATALOGS`.

## App strings

- SwiftUI literals such as `Text("…")` and `Button("…")` are localized automatically.
- Strings built in code use `String(localized:)`. Ternaries of literals do too, because otherwise they become plain `String`s and aren't translated.
- Interpolations become `%@` for strings and `%lld` for integers in the catalog's keys. English plural forms live in the catalog as `variations`, such as "Blocking %lld sites".
- `xcodebuild` doesn't sync the catalog, so add new keys to `Localizable.xcstrings` by hand. To list the exact keys the code uses, build, then run `jq` over `build/**/Objects-normal/*/*.stringsdata`.
- Language names in the picker are written in their own language ("English", "简体中文"), so they're recognizable whatever the current language is.

## Extension strings

These are the keys:

- `extensionDescription`, used in both manifests;
- `blockedTitle`, `thisSiteIsBlocked` and `keepingYouFocused`, used by the blocked page;
- `pageLanguage`, the page's `lang` attribute.

`blocked.js` falls back to the English text in `blocked.html` whenever `getMessage` returns an empty string. The browser picks the locale itself, not the app's language setting.

## The language picker

`AppLanguage` writes `AppleLanguages` to the app's own defaults. That's the same place System Settings' per-app language uses, so the two stay in sync. Choosing "System Language" removes the key.

macOS only reads the language at launch. So when the choice would change the language (`needsRelaunch`), Settings offers **Relaunch Now**. `AppLanguage.relaunch()` starts a small shell that waits for this process to exit and reopens the bundle, then the app quits.

To see the Chinese UI without changing the saved setting:

```bash
build/Build/Products/Debug/Disciplined.app/Contents/MacOS/Disciplined -AppleLanguages '(zh-Hans)'
```

## Adding a language

Do all three:

- add a case to `AppLanguage`;
- add its translations to every key in `Localizable.xcstrings`;
- add an `Extension/_locales/<code>/messages.json` with every key above.

## Related

- [browser-extension.md](browser-extension.md#the-blocked-page).
