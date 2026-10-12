// Runs Extension/background.js against a fake `chrome` API. Run with `node --test Tests/Extension/*.test.mjs`.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";

const source = await readFile(new URL("../../Extension/background.js", import.meta.url), "utf8");
const BLOCKED_PAGE = "chrome-extension://ext/blocked.html";
// Objects made inside the sandbox have its prototypes, which deepEqual treats as different.
const plain = (value) => JSON.parse(JSON.stringify(value));

function loadExtension({ savedRules = [], tabs = [] } = {}) {
  const listeners = {};
  const event = (name) => ({ addListener: (fn) => (listeners[name] = fn) });
  let rules = savedRules;
  const state = { redirected: [], storage: {}, alarms: [], connections: 0 };

  const chrome = {
    runtime: {
      getURL: (path) => `chrome-extension://ext/${path}`,
      connectNative: () => {
        state.connections++;
        return { onMessage: event("message"), onDisconnect: event("disconnect") };
      },
      onStartup: event("startup"),
    },
    declarativeNetRequest: {
      getDynamicRules: async () => rules,
      updateDynamicRules: async ({ removeRuleIds, addRules }) => {
        rules = rules.filter((rule) => !removeRuleIds.includes(rule.id)).concat(addRules);
      },
    },
    tabs: {
      query: async () => tabs,
      update: (id, { url }) => state.redirected.push([id, url]),
      onUpdated: event("tabUpdated"),
    },
    alarms: { create: (name) => state.alarms.push(name), onAlarm: event("alarm") },
    storage: { local: { set: (values) => Object.assign(state.storage, values) } },
  };
  vm.runInNewContext(source, { chrome, URL, console: { warn() {} } });

  // Lets the extension's promise chains finish.
  const settle = () => new Promise((resolve) => setImmediate(resolve));
  return {
    state,
    rules: () => plain(rules),
    async send(message) {
      listeners.message(message);
      await settle();
    },
    async navigate(tabId, url) {
      listeners.tabUpdated(tabId, { url });
      await settle();
    },
    async disconnect() {
      listeners.disconnect({});
      await settle();
    },
    async alarm(name) {
      listeners.alarm({ name });
      await settle();
    },
  };
}

test("blocks a domain and its subdomains, but not lookalikes", async () => {
  const ext = loadExtension();
  await ext.send({ domains: ["example.com"] });
  const urls = [
    "https://example.com/",
    "https://www.example.com/watch?v=1",
    "http://a.b.example.com:8080/",
    "https://notexample.com/",
    "https://example.com.evil.net/",
    "https://example.org/",
    "not a url",
  ];
  for (const [i, url] of urls.entries()) await ext.navigate(i, url);
  assert.deepEqual(ext.state.redirected, [[0, BLOCKED_PAGE], [1, BLOCKED_PAGE], [2, BLOCKED_PAGE]]);
});

test("installs one redirect rule with only valid domains", async () => {
  const ext = loadExtension();
  await ext.send({ domains: ["a.com", "a.com", "Example.com", 42, "evil.com 127.0.0.1", "", "b.org"] });
  assert.deepEqual(ext.rules(), [{
    id: 1,
    priority: 1,
    action: { type: "redirect", redirect: { extensionPath: "/blocked.html" } },
    condition: { requestDomains: ["a.com", "b.org"], resourceTypes: ["main_frame", "sub_frame"] },
  }]);
});

test("an empty list unblocks everything", async () => {
  const ext = loadExtension();
  await ext.send({ domains: ["a.com"] });
  await ext.send({ domains: [] });
  assert.deepEqual(ext.rules(), []);
  await ext.navigate(1, "https://a.com/");
  assert.deepEqual(ext.state.redirected, []);
});

test("redirects tabs that are already open when the list arrives", async () => {
  const ext = loadExtension({ tabs: [{ id: 1, url: "https://a.com/x" }, { id: 2, url: "https://b.com/" }] });
  await ext.send({ domains: ["a.com"] });
  assert.deepEqual(ext.state.redirected, [[1, BLOCKED_PAGE]]);
});

test("keeps blocking after a restart while the app can't be reached", async () => {
  const ext = loadExtension({ savedRules: [{ id: 1, condition: { requestDomains: ["a.com"] } }] });
  await ext.navigate(1, "https://www.a.com/");
  assert.deepEqual(ext.state.redirected, [[1, BLOCKED_PAGE]]);
});

test("reconnects to the app after it disconnects", async () => {
  const ext = loadExtension();
  assert.equal(ext.state.connections, 1);
  await ext.disconnect();
  assert.deepEqual(ext.state.alarms, ["reconnect"]);
  await ext.alarm("reconnect");
  assert.equal(ext.state.connections, 2);
});

// blocked.js puts these straight into CSS custom properties.
test("saves only well-formed accent colors", async () => {
  const ext = loadExtension();
  for (const accent of [
    { light: "red", dark: "#000000" },
    { light: "#FFFFFF", dark: "#000000" },
    { light: "#fff", dark: "#000" },
    { light: "#123456; background: url(x)", dark: "#000000" },
    { light: "#123456" },
  ]) {
    await ext.send({ accent });
  }
  assert.deepEqual(plain(ext.state.storage), {});
  await ext.send({ accent: { light: "#5856d6", dark: "#5e5ce6", extra: "x" } });
  assert.deepEqual(plain(ext.state.storage), { accent: { light: "#5856d6", dark: "#5e5ce6" } });
});
