// Disciplined — blocks the sites on the list the Mac app keeps.
//
// The app's native messaging host sends {domains: [...]} on connect and whenever the list changes.
// Blocking uses dynamic declarativeNetRequest rules, which persist across browser restarts, so sites
// stay blocked even while the app can't be reached.
//
// Shared with the Firefox/Zen build (FirefoxExtension/manifest.json), where `browser` is the
// promise-based namespace.

const api = globalThis.browser ?? chrome;

const HOST = "com.disciplined.mac";
const BLOCKED_PAGE = api.runtime.getURL("blocked.html");
// Must match Domain.pattern in the app.
const DOMAIN_RE = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;

let blocked = [];
let port = null;

// After the service worker restarts, recover the list from the rules it saved.
const ready = api.declarativeNetRequest.getDynamicRules().then((rules) => {
  blocked = rules.flatMap((rule) => rule.condition.requestDomains ?? []);
});

function blockedPageFor(domain) {
  return `${BLOCKED_PAGE}?site=${encodeURIComponent(domain)}`;
}

function blockedDomain(url) {
  let host;
  try {
    host = new URL(url).hostname;
  } catch {
    return undefined;
  }
  return blocked.find((d) => host === d || host.endsWith(`.${d}`));
}

// Rules only catch new page loads; this also covers tabs that are already open and in-page navigation.
function blockTabIfNeeded(tabId, url) {
  if (!url || url.startsWith(BLOCKED_PAGE)) return;
  const domain = blockedDomain(url);
  if (domain) api.tabs.update(tabId, { url: blockedPageFor(domain) });
}

async function applyList(domains) {
  await ready;
  blocked = [...new Set(domains.filter((d) => typeof d === "string" && DOMAIN_RE.test(d)))];
  const old = await api.declarativeNetRequest.getDynamicRules();
  await api.declarativeNetRequest.updateDynamicRules({
    removeRuleIds: old.map((rule) => rule.id),
    addRules: blocked.map((domain, i) => ({
      id: i + 1,
      priority: 1,
      action: { type: "redirect", redirect: { extensionPath: `/blocked.html?site=${encodeURIComponent(domain)}` } },
      condition: { requestDomains: [domain], resourceTypes: ["main_frame", "sub_frame"] },
    })),
  });
  for (const tab of await api.tabs.query({})) blockTabIfNeeded(tab.id, tab.url);
}

function connect() {
  port = api.runtime.connectNative(HOST);
  port.onMessage.addListener((message) => {
    if (Array.isArray(message?.domains)) applyList(message.domains);
  });
  port.onDisconnect.addListener((p) => {
    // Chrome reports the reason in lastError, Firefox on the port.
    console.warn("Disciplined app disconnected:", (p.error ?? api.runtime.lastError)?.message);
    port = null;
    api.alarms.create("reconnect", { delayInMinutes: 0.5 });
  });
}

api.tabs.onUpdated.addListener(async (tabId, change) => {
  if (!change.url) return;
  await ready;
  blockTabIfNeeded(tabId, change.url);
});

api.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "reconnect" && !port) connect();
});

// Wakes the service worker when the browser starts; the connect below does the rest.
api.runtime.onStartup.addListener(() => {});

// An open native messaging port keeps the service worker alive.
connect();
