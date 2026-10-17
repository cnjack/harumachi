'use strict';
// Executes generated review UI in a DOM implementation without launching a browser.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const timers = require('node:timers');
const { parseHTML } = require('linkedom');

function createReviewEnvironment(html, options = {}) {
  const { document, window } = parseHTML(html);
  const storage = options.storage || new Map();
  const downloads = [], alerts = [], confirms = [], copied = [];
  const domSelect = window.HTMLSelectElement.prototype;
  Object.defineProperty(domSelect, 'value', {
    configurable: true,
    get() { const opts = Array.from(this.querySelectorAll('option')); const opt = opts.find(o => o.hasAttribute('selected')) || opts[0]; return opt ? (opt.getAttribute('value') ?? opt.textContent) : ''; },
    set(value) { for (const opt of this.querySelectorAll('option')) { if ((opt.getAttribute('value') ?? opt.textContent) === String(value)) opt.setAttribute('selected', ''); else opt.removeAttribute('selected'); } }
  });
  Object.defineProperty(domSelect, 'selectedIndex', {
    configurable: true,
    get() { return Array.from(this.querySelectorAll('option')).findIndex(o => o.value === this.value); },
    set(index) { const opt = this.querySelectorAll('option')[index]; if (opt) this.value = opt.value; }
  });
  domSelect.add = function (option) { this.appendChild(option); };
  Object.defineProperty(window.HTMLInputElement.prototype, 'checked', {
    configurable: true,
    get() { return this.hasAttribute('checked'); },
    set(value) {
      if (value && this.type === 'radio' && this.name) {
        for (const radio of document.querySelectorAll('input[type="radio"]')) if (radio !== this && radio.name === this.name) radio.removeAttribute('checked');
      }
      if (value) this.setAttribute('checked', ''); else this.removeAttribute('checked');
    }
  });
  Object.defineProperty(window.HTMLAnchorElement.prototype, 'download', {
    configurable: true,
    get() { return this.getAttribute('download') || ''; },
    set(value) { this.setAttribute('download', value); }
  });
  const fakeStorage = {
    getItem(key) { if (options.storageReadFails) throw new Error('storage denied'); return storage.get(key) ?? null; },
    setItem(key, value) { if (options.storageWriteFails) throw new Error('quota exceeded'); storage.set(key, String(value)); },
    removeItem(key) { storage.delete(key); }
  };
  const blobs = new Map();
  let blobIndex = 0;
  const nativeClick = window.HTMLElement.prototype.click;
  window.HTMLElement.prototype.click = function () {
    if (this.tagName === 'A' && this.hasAttribute('download')) {
      downloads.push({ filename: this.getAttribute('download'), blob: blobs.get(this.href) });
      return;
    }
    return nativeClick.call(this);
  };
  window.HTMLElement.prototype.scrollIntoView = function () {};
  window.HTMLElement.prototype.focus = function () { document.activeElement = this; };
  window.HTMLElement.prototype.getBoundingClientRect = function () { return { left: 0, top: 0, width: 1000, height: 700, right: 1000, bottom: 700 }; };
  class FakeURL extends URL {}
  FakeURL.createObjectURL = blob => { const key = 'blob:offline-' + (++blobIndex); blobs.set(key, blob); return key; };
  FakeURL.revokeObjectURL = () => {};
  const fakeNavigator = { clipboard: { writeText: async text => { copied.push(text); } } };
  const fakeLocation = { protocol: 'file:', href: 'file:///character-review-test/index.html', hash: '' };
  function Option(text, value) { const opt = document.createElement('option'); opt.textContent = text; opt.value = value ?? text; return opt; }
  const globals = {
    window, document, navigator: fakeNavigator, location: fakeLocation, localStorage: fakeStorage,
    console, setTimeout: (fn, ms) => { const timer = timers.setTimeout(fn, ms); timer.unref(); return timer; }, clearTimeout: timers.clearTimeout, setInterval: timers.setInterval, clearInterval: timers.clearInterval,
    Blob, File, URL: FakeURL, Option, Event: window.Event, CustomEvent: window.CustomEvent,
    HTMLElement: window.HTMLElement, HTMLInputElement: window.HTMLInputElement,
    Node: window.Node, Element: window.Element, crypto, structuredClone,
    alert: message => alerts.push(String(message)),
    confirm: message => { confirms.push(String(message)); return options.confirmResult ?? true; },
    prompt: () => null,
    requestAnimationFrame: callback => { const timer = timers.setTimeout(callback, 0); timer.unref(); return timer; }, cancelAnimationFrame: timers.clearTimeout,
    matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} })
  };
  for (const [key, value] of Object.entries(globals)) {
    if (key !== 'window' && key !== 'document') {
      try { Object.defineProperty(window, key, { value, configurable: true, writable: true }); } catch (_) {}
    }
  }
  const context = vm.createContext(globals);
  const scriptNodes = Array.from(document.querySelectorAll('script'));
  for (const script of scriptNodes) {
    if (script.type && script.type !== 'text/javascript' && script.type !== 'application/javascript') continue;
    const src = script.getAttribute('src');
    const source = src ? fs.readFileSync(path.resolve(__dirname, src), 'utf8') : script.textContent;
    vm.runInContext(source, context, { filename: src || 'review-fixture.html', timeout: 15000 });
    if (context.ReviewModel) window.ReviewModel = context.ReviewModel;
  }
  document.dispatchEvent(new window.Event('DOMContentLoaded'));
  return { document, window, context, storage, downloads, alerts, confirms, copied,
    evaluate: code => vm.runInContext(code, context, { timeout: 15000 }),
    event(id, kind) { document.getElementById(id).dispatchEvent(new window.Event(kind, { bubbles: true })); }
  };
}
module.exports = { createReviewEnvironment };
