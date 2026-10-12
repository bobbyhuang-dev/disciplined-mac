const api = globalThis.browser ?? chrome;
const i18n = api.i18n;

// getMessage returns "" until the browser loads _locales, e.g. when an unpacked
// extension's files changed without a reload, so fall back to English then.
const msg = (key, fallback) => i18n.getMessage(key) || fallback;

// The page never names the site: its title shows in the tab bar, window list and screen shares.
for (const [id, key] of [["heading", "thisSiteIsBlocked"], ["message", "keepingYouFocused"]]) {
  const element = document.getElementById(id);
  element.textContent = msg(key, element.textContent);
}
document.documentElement.lang = msg("pageLanguage", "en");
document.title = msg("blockedTitle", document.title);

// The app's accent color, which background.js saves whenever the app sends it. The page stays hidden
// until it's set, so it doesn't flash the default color first.
const COLOR_RE = /^#[0-9a-f]{6}$/;

function applyAccent(accent) {
  for (const mode of ["light", "dark"]) {
    if (COLOR_RE.test(accent?.[mode])) document.documentElement.style.setProperty(`--accent-${mode}`, accent[mode]);
  }
}

document.body.classList.add("loading");
// `storage` is missing while Chrome still has the extension's previous manifest.
new Promise((resolve) => resolve(api.storage.local.get("accent")))
  .then((saved) => applyAccent(saved?.accent))
  .catch(() => {})
  .finally(() => document.body.classList.remove("loading"));

api.storage?.onChanged.addListener((changes, area) => {
  if (area === "local" && changes.accent) applyAccent(changes.accent.newValue);
});
