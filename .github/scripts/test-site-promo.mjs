// Exercises the Black Friday window in site/index.html by running the inline
// script. The window stays in that one object; this file only checks it.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const htmlPath = fileURLToPath(new URL("../../site/index.html", import.meta.url));
const html = readFileSync(htmlPath, "utf8");
const scriptMatch = html.match(/<script id="shoutkit-bf2026">([\s\S]*?)<\/script>/);
assert.ok(scriptMatch, "site/index.html should contain #shoutkit-bf2026");
const script = scriptMatch[1];

const TESTFLIGHT = "https://testflight.apple.com/join/ZBSBTbRU";

function loadApi() {
  const sandbox = {
    document: {
      getElementById() {
        return null;
      },
      querySelector() {
        return null;
      },
      querySelectorAll() {
        return [];
      },
      addEventListener() {},
    },
    location: { search: "" },
    localStorage: {
      getItem() {
        return null;
      },
      setItem() {},
    },
    console,
    Date,
    Intl,
    URLSearchParams,
  };
  const context = createContext(sandbox);
  runInContext(script, context, { filename: "site/index.html" });
  assert.ok(sandbox.SHOUTKIT_BF2026, "script should publish SHOUTKIT_BF2026");
  return sandbox.SHOUTKIT_BF2026;
}

const api = loadApi();

function memoryStorage(initial) {
  const map = new Map(initial);
  return {
    getItem(key) {
      if (this.throwGet) throw new Error("denied");
      return map.has(key) ? map.get(key) : null;
    },
    setItem(key, value) {
      if (this.throwSet) throw new Error("denied");
      map.set(key, String(value));
    },
    map,
  };
}

function element(id) {
  return {
    id,
    hidden: true,
    kids: [],
    listeners: {},
    focused: null,
    addEventListener(type, fn) {
      this.listeners[type] = fn;
    },
    contains(node) {
      return node === this || this.kids.includes(node);
    },
    focus(opts) {
      this.focused = opts === undefined ? true : opts;
    },
  };
}

function page() {
  const dismiss = element("bf-dismiss");
  const sectionDismiss = element("bf-section-dismiss");
  const link = element("bf-link");
  const banner = element("bf-promo");
  const section = element("bf2026");
  const brand = element("brand");
  const holiday = element("promo-bar");
  holiday.hidden = false;
  banner.kids.push(dismiss, link);
  section.kids.push(sectionDismiss);
  const doc = {
    holiday,
    getElementById(id) {
      if (id === "bf-promo") return banner;
      if (id === "bf2026") return section;
      if (id === "promo-bar") return holiday;
      return null;
    },
    querySelector(selector) {
      return selector === "a.brand" ? brand : null;
    },
    querySelectorAll(selector) {
      return selector === "[data-bf-dismiss]" ? [dismiss, sectionDismiss] : [];
    },
    addEventListener(type, fn) {
      this.listeners[type] = fn;
    },
    listeners: {},
  };
  return { doc, banner, section, dismiss, sectionDismiss, link, brand, holiday };
}

test("the window is defined once, in Los Angeles, for Black Friday through December 1", () => {
  assert.equal(api.config.timeZone, "America/Los_Angeles");
  assert.equal(api.config.start, "2026-11-27T00:00");
  assert.equal(api.config.end, "2026-12-01T23:59");
  assert.equal(html.split("2026-11-27T00:00").length - 1, 1);
  assert.equal(html.split("2026-12-01T23:59").length - 1, 1);
  assert.equal(html.includes("document.cookie"), false);
  assert.equal(script.includes("promo-bar"), false);
  assert.equal(html.includes("<script src"), false);
  assert.match(html, /property="og:image" content="https:\/\/cascadiacollections\.github\.io\/shoutkit\/og-image\.png"/);
});

test("the banner and section ship hidden, with the existing TestFlight link", () => {
  assert.match(html, /<aside id="bf-promo" class="bf-banner" hidden /);
  assert.match(html, /<section id="bf2026" class="bf-section" hidden /);
  assert.match(html, /\.bf-banner\[hidden\] \{ display: none; \}/);
  assert.match(html, /\.bf-section\[hidden\] \{ display: none; \}/);
  assert.equal((html.match(/<button[^>]*data-bf-dismiss/g) || []).length, 2);
  const promo = html.slice(html.indexOf('id="bf-promo"'), html.indexOf('id="promo-bar"'));
  const section = html.slice(html.indexOf('id="bf2026"'), html.indexOf('id="holidays"'));
  assert.equal(promo.includes(TESTFLIGHT), true);
  assert.equal(section.includes(TESTFLIGHT), true);
  assert.equal(promo.includes("appstore"), false);
  assert.equal(section.includes("shoutkit-android"), false);
});

test("wall-clock minutes use America/Los_Angeles, not the host zone", () => {
  const zone = "America/Los_Angeles";
  assert.equal(api.wallClockMinute(new Date("2026-11-27T07:59:00.000Z"), zone), "2026-11-26T23:59");
  assert.equal(api.wallClockMinute(new Date("2026-11-27T08:00:00.000Z"), zone), "2026-11-27T00:00");
  assert.equal(api.wallClockMinute(new Date("2026-12-02T07:59:59.000Z"), zone), "2026-12-01T23:59");
  assert.equal(api.wallClockMinute(new Date("2026-12-02T08:00:00.000Z"), zone), "2026-12-02T00:00");
});

test("the window is inclusive of the first and last minute and closed outside it", () => {
  const storage = memoryStorage();
  const before = new Date("2026-11-27T07:59:00.000Z");
  const start = new Date("2026-11-27T08:00:00.000Z");
  const end = new Date("2026-12-02T07:59:59.000Z");
  const after = new Date("2026-12-02T08:00:00.000Z");
  assert.equal(api.isPromoWindow(before), false);
  assert.equal(api.isPromoWindow(start), true);
  assert.equal(api.isPromoWindow(end), true);
  assert.equal(api.isPromoWindow(after), false);
  assert.equal(api.shouldShow(before, "", storage), false);
  assert.equal(api.shouldShow(start, "", storage), true);
  assert.equal(api.shouldShow(after, "", storage), false);
});

test("?promo=bf2026 shows the notice outside the window and ignores dismissal", () => {
  const storage = memoryStorage([[api.config.storageKey, "1"]]);
  const after = new Date("2026-12-02T08:00:00.000Z");
  assert.equal(api.isPromoPreview("?promo=bf2026"), true);
  assert.equal(api.isPromoPreview("?utm=1&promo=bf2026"), true);
  assert.equal(api.isPromoPreview("?promo=BF2026"), false);
  assert.equal(api.isPromoPreview("?promo=other"), false);
  assert.equal(api.isPromoPreview(""), false);
  assert.equal(api.shouldShow(after, "?promo=bf2026", storage), true);
  assert.equal(api.shouldShow(after, "?promo=other", storage), false);
});

test("dismissal is remembered inside the window, and a blocked store still shows it", () => {
  const start = new Date("2026-11-27T08:00:00.000Z");
  const stored = memoryStorage([[api.config.storageKey, "1"]]);
  assert.equal(api.shouldShow(start, "", stored), false);
  assert.equal(api.shouldShow(start, "?promo=bf2026", stored), false);
  const blocked = memoryStorage();
  blocked.throwGet = true;
  assert.equal(api.shouldShow(start, "", blocked), true);
  assert.equal(api.isPromoWindow(new Date("not-a-date")), false);
});

test("applyPromo leaves the page alone outside the window", () => {
  const { doc, banner, section, holiday } = page();
  const shown = api.applyPromo(doc, { search: "" }, memoryStorage(), new Date("2026-11-27T07:59:00.000Z"));
  assert.equal(shown, false);
  assert.equal(banner.hidden, true);
  assert.equal(section.hidden, true);
  assert.equal(holiday.hidden, false);
  assert.equal(doc.listeners.keydown, undefined);
});

test("preview shows both parts, and dismissing does not stick", () => {
  const { doc, banner, section, dismiss, brand } = page();
  const storage = memoryStorage();
  const shown = api.applyPromo(doc, { search: "?promo=bf2026" }, storage, new Date("2026-11-23T12:00:00.000Z"));
  assert.equal(shown, true);
  assert.equal(banner.hidden, false);
  assert.equal(section.hidden, false);
  dismiss.listeners.click();
  assert.equal(banner.hidden, true);
  assert.equal(section.hidden, true);
  assert.equal(storage.map.has(api.config.storageKey), false);
  assert.equal(brand.focused.preventScroll, true);
});

test("inside the window, dismiss writes localStorage and Escape works only from the notice", () => {
  const { doc, banner, section, sectionDismiss, link } = page();
  const storage = memoryStorage();
  const now = new Date("2026-11-28T20:00:00.000Z");
  assert.equal(api.applyPromo(doc, { search: "" }, storage, now), true);
  const outside = { key: "Escape", target: { id: "elsewhere" }, preventDefault() { this.defaultPrevented = true; } };
  doc.listeners.keydown(outside);
  assert.equal(banner.hidden, false);
  assert.equal(outside.defaultPrevented, undefined);

  const inside = { key: "Escape", target: link, preventDefault() { this.defaultPrevented = true; } };
  doc.listeners.keydown(inside);
  assert.equal(inside.defaultPrevented, true);
  assert.equal(banner.hidden, true);
  assert.equal(section.hidden, true);
  assert.equal(storage.map.get(api.config.storageKey), "1");

  storage.map.delete(api.config.storageKey);
  banner.hidden = false;
  section.hidden = false;
  const shifted = { key: "Escape", shiftKey: true, target: link, preventDefault() {} };
  doc.listeners.keydown(shifted);
  assert.equal(banner.hidden, false);

  sectionDismiss.listeners.click();
  assert.equal(storage.map.get(api.config.storageKey), "1");
  assert.equal(api.applyPromo(doc, { search: "" }, storage, now), false);
});

test("a blocked write still hides the notice", () => {
  const { doc, banner } = page();
  const storage = memoryStorage();
  storage.throwSet = true;
  api.applyPromo(doc, { search: "" }, storage, new Date("2026-11-28T20:00:00.000Z"));
  doc.listeners.keydown({
    key: "Escape",
    target: banner,
    preventDefault() {},
  });
  assert.equal(banner.hidden, true);
});
