---
summary: How the accent color chosen in Settings tints the app and reaches the extension's blocked page through appThemeColors, the native host and storage.local.
---

# Accent color

## Purpose

The accent color you pick in Settings → General → Accent color tints the whole app and the blocked page in browsers, so the two look like one product.

## Components

- `Sources/AppTheme.swift` — `AppTheme` (the choices, `saveColors()`, `savedColors`, `hex`) and `ThemePicker`.
- `Sources/NativeHost.swift` — sends the saved colors.
- `Extension/background.js` — validates and stores them.
- `Extension/blocked.js`, `Extension/blocked.css` — apply them.

## In the app

`AppTheme` has five system colors (indigo, blue, teal, orange, pink) plus `system`, which follows System Settings' accent (`NSColor.controlAccentColor`). The choice is saved as `appTheme` and defaults to indigo.

It applies through `.tint(theme.color)` on the window roots, which sheets and popovers inherit. Views that need the color directly use `.tint` as a shape style, or `theme.color` when they need a gradient. The app icon and the site-letter tiles keep their own colors.

## To the blocked page

1. `BlockerModel.refresh()` calls `AppTheme.saveColors()` every second. It resolves the color to `#rrggbb` in sRGB, once under the `aqua` appearance and once under `darkAqua`. It saves the pair as `appThemeColors`, but only when the pair changed. Polling catches both a new choice in Settings and a new system accent.
2. The native host reads `AppTheme.savedColors` and sends `{accent: {light, dark}}` whenever it changes. It can't resolve the color itself: outside a running app, `NSColor.controlAccentColor` keeps whatever value it had when the process started.
3. `background.js` stores the pair in `storage.local`, but only if both are lowercase `#rrggbb`. They go straight into CSS, so nothing else is allowed through.
4. `blocked.js` sets `--accent-light` and `--accent-dark` on the page, both from storage at load and on `storage.onChanged`. `blocked.css` uses one or the other depending on `prefers-color-scheme`.
5. The page content stays hidden until the colors load, so it doesn't flash the fallback. The fallbacks in `blocked.css`, `#6155f5` and `#6d7cff`, are macOS 26's indigo.

## Known limitations

- Filter-mode Firefox shows its own error page, so the color doesn't reach it (see [root-helper.md](root-helper.md#the-two-browser-modes)).
- `appThemeColors` is only updated while the app runs. A new system accent chosen while the app is closed reaches the blocked page the next time the app runs.

## Related

- [native-messaging-host.md](native-messaging-host.md), [browser-extension.md](browser-extension.md#the-blocked-page).
