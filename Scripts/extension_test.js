// Usage: node Scripts/extension_test.js Extension/chrome/background.js
// Runs the real background.js against a fake Chrome and a fake native host that applies Panda's rules.
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');

function makeEvent() { const ls = []; return { addListener: (f) => ls.push(f), fire: (...a) => ls.forEach((f) => f(...a)) }; }

function makeWorld(settings) {
  settings.custom = settings.custom || [];
  const tabs = new Map();
  const removed = [], created = [], hostMessages = [];
  const portListeners = [];
  function classify(url) {
    const u = new URL(url); const h = u.hostname;
    if (h === 'instagram.com' || h.endsWith('.instagram.com')) return settings.instagram ? 'instagram' : null;
    if (h === 'youtube.com' || h.endsWith('.youtube.com')) {
      if (u.pathname === '/shorts' || u.pathname.startsWith('/shorts/')) return settings.shorts ? 'shorts' : null;
      return null;
    }
    const bare = h.replace(/^www\./, '');
    if (settings.custom.some((c) => bare === c || bare.endsWith('.' + c))) return 'custom';
    return null;
  }
  const port = {
    onMessage: { addListener: (f) => portListeners.push(f) },
    onDisconnect: { addListener: () => {} },
    postMessage(m) {
      hostMessages.push(m);
      if (m.type === 'hello') setTimeout(() => portListeners.forEach((f) => f({ type: 'hello', appRunning: true, hosts: settings.custom.slice() })), 1);
      if (m.type === 'check') {
        const kind = classify(m.url);
        setTimeout(() => portListeners.forEach((f) => f({ type: 'verdict', id: m.id, block: !!kind, kind: kind || '', delayMs: kind ? settings.delay : 0 })), 2);
      }
    },
  };
  const chrome = {
    runtime: { connectNative: () => port, lastError: null, onStartup: makeEvent(), onInstalled: makeEvent(), onMessage: makeEvent() },
    tabs: {
      onUpdated: makeEvent(), onCreated: makeEvent(), onActivated: makeEvent(),
      async get(id) { if (!tabs.has(id)) throw new Error('no tab'); return { ...tabs.get(id) }; },
      async query({ windowId }) { return [...tabs.values()].filter((t) => t.windowId === windowId); },
      async create(o) { const id = 1000 + created.length; created.push(o); tabs.set(id, { id, windowId: o.windowId, url: 'chrome://newtab/', index: 0 }); return tabs.get(id); },
      async remove(id) { if (!tabs.has(id)) throw new Error('no tab'); tabs.delete(id); removed.push(id); },
    },
    windows: { async get(id) { return { left: 10, top: 30, width: 1200, tabs: [...tabs.values()].filter((t) => t.windowId === id) }; } },
    webNavigation: { onHistoryStateUpdated: makeEvent(), onCommitted: makeEvent() },
  };
  vm.runInNewContext(src, { chrome, URL, setTimeout, clearTimeout, console, Promise, Map, Set });
  const pushSites = (hosts) => { settings.custom = hosts; portListeners.forEach((f) => f({ type: 'sites', hosts })); };
  return { chrome, tabs, removed, created, hostMessages, pushSites };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let failed = 0;
function check(name, cond, extra = '') { console.log(`  ${cond ? 'ok  ' : 'FAIL'} ${name} ${cond ? '' : extra}`); if (!cond) failed++; }

(async () => {
  let w = makeWorld({ instagram: true, shorts: true, delay: 60 });
  w.tabs.set(1, { id: 1, windowId: 1, index: 0, url: 'https://example.com/' });
  w.tabs.set(2, { id: 2, windowId: 1, index: 1, url: 'https://www.instagram.com/' });
  w.chrome.tabs.onUpdated.fire(2, { url: 'https://www.instagram.com/' }, w.tabs.get(2));
  await sleep(30);
  check('instagram tab still open while panda is on his way', w.tabs.has(2));
  await sleep(120);
  check('instagram tab closed', w.removed.includes(2) && !w.tabs.has(2));
  check('closed event reported to the app', w.hostMessages.some((m) => m.type === 'closed' && m.kind === 'instagram'));
  check('geometry sent with the check', w.hostMessages.some((m) => m.type === 'check' && m.left === 10 && m.width === 1200 && m.index === 1 && m.count === 2));

  w.tabs.set(3, { id: 3, windowId: 1, index: 1, url: 'https://www.youtube.com/watch?v=abc' });
  w.chrome.tabs.onUpdated.fire(3, { url: 'https://www.youtube.com/watch?v=abc' }, w.tabs.get(3));
  await sleep(150);
  check('normal video left open', w.tabs.has(3));

  // In-page navigation from that video to a Short (no page load)
  w.tabs.get(3).url = 'https://www.youtube.com/shorts/XYZ';
  w.chrome.webNavigation.onHistoryStateUpdated.fire({ frameId: 0, tabId: 3, url: 'https://www.youtube.com/shorts/XYZ' });
  w.chrome.tabs.onUpdated.fire(3, { url: 'https://www.youtube.com/shorts/XYZ' }, w.tabs.get(3));
  await sleep(200);
  check('short reached by in-page navigation closed', w.removed.includes(3));
  check('counted once, not twice', w.hostMessages.filter((m) => m.type === 'closed' && m.kind === 'shorts').length === 1);

  // Address changes to a Short while the check for the normal video is still in flight
  w.tabs.set(4, { id: 4, windowId: 1, index: 1, url: 'https://www.youtube.com/watch?v=1' });
  w.chrome.tabs.onUpdated.fire(4, { url: 'https://www.youtube.com/watch?v=1' }, w.tabs.get(4));
  w.tabs.get(4).url = 'https://www.youtube.com/shorts/LATE';
  w.chrome.tabs.onUpdated.fire(4, { url: 'https://www.youtube.com/shorts/LATE' }, w.tabs.get(4));
  await sleep(250);
  check('short that arrived mid-check closed', w.removed.includes(4));

  // User leaves Instagram before the panda arrives
  w.tabs.set(5, { id: 5, windowId: 1, index: 1, url: 'https://www.instagram.com/' });
  w.chrome.tabs.onUpdated.fire(5, { url: 'https://www.instagram.com/' }, w.tabs.get(5));
  await sleep(20);
  w.tabs.get(5).url = 'https://docs.google.com/document/d/1';
  await sleep(150);
  check('tab kept when the user already left Instagram', w.tabs.has(5));

  // Only tab in its window: a fresh tab is left behind
  w.tabs.set(6, { id: 6, windowId: 2, index: 0, url: 'https://www.instagram.com/reels/' });
  w.chrome.tabs.onCreated.fire(w.tabs.get(6));
  await sleep(200);
  check('only tab closed and replaced with a new tab', w.removed.includes(6) && w.created.some((c) => c.windowId === 2));

  // Switching to an Instagram tab that was open before protection came on
  w.tabs.set(7, { id: 7, windowId: 1, index: 2, url: 'https://www.instagram.com/direct/' });
  w.chrome.tabs.onActivated.fire({ tabId: 7 });
  await sleep(200);
  check('old instagram tab closed when switched to', w.removed.includes(7));

  // Toggles off
  w = makeWorld({ instagram: false, shorts: false, delay: 0 });
  w.tabs.set(1, { id: 1, windowId: 1, index: 0, url: 'https://www.instagram.com/' });
  w.tabs.set(2, { id: 2, windowId: 1, index: 1, url: 'https://www.youtube.com/shorts/x' });
  w.chrome.tabs.onUpdated.fire(1, { url: 'https://www.instagram.com/' }, w.tabs.get(1));
  w.chrome.tabs.onUpdated.fire(2, { url: 'https://www.youtube.com/shorts/x' }, w.tabs.get(2));
  await sleep(100);
  check('nothing closed with both toggles off', w.removed.length === 0);

  // Ordinary browsing never reaches the host
  const before = w.hostMessages.filter((m) => m.type === 'check').length;
  w.tabs.set(3, { id: 3, windowId: 1, index: 2, url: 'https://en.wikipedia.org/wiki/Giant_panda' });
  w.chrome.tabs.onUpdated.fire(3, { url: 'https://en.wikipedia.org/wiki/Giant_panda' }, w.tabs.get(3));
  await sleep(50);
  check('ordinary sites are never sent to the app', w.hostMessages.filter((m) => m.type === 'check').length === before);

  // Your own blocklist
  w = makeWorld({ instagram: true, shorts: true, delay: 0, custom: ['reddit.com'] });
  w.tabs.set(1, { id: 1, windowId: 1, index: 0, url: 'https://example.com/' });
  w.tabs.set(2, { id: 2, windowId: 1, index: 1, url: 'https://www.reddit.com/r/all/' });
  w.chrome.tabs.onUpdated.fire(2, { url: 'https://www.reddit.com/r/all/' }, w.tabs.get(2));
  await sleep(120);
  check('site from the blocklist closed', w.removed.includes(2));
  check('counted as a custom site', w.hostMessages.some((m) => m.type === 'closed' && m.kind === 'custom'));

  w.tabs.set(3, { id: 3, windowId: 1, index: 1, url: 'https://news.ycombinator.com/' });
  w.chrome.tabs.onUpdated.fire(3, { url: 'https://news.ycombinator.com/' }, w.tabs.get(3));
  await sleep(80);
  check('site not on the list left alone', w.tabs.has(3));

  w.pushSites(['reddit.com', 'ycombinator.com']);
  w.chrome.tabs.onUpdated.fire(3, { url: 'https://news.ycombinator.com/' }, w.tabs.get(3));
  await sleep(120);
  check('site added while the browser is running closed', w.removed.includes(3));

  w.pushSites([]);
  w.tabs.set(4, { id: 4, windowId: 1, index: 1, url: 'https://old.reddit.com/' });
  w.chrome.tabs.onUpdated.fire(4, { url: 'https://old.reddit.com/' }, w.tabs.get(4));
  await sleep(80);
  check('site removed from the list is allowed again', w.tabs.has(4));

  console.log(failed ? `\n${failed} FAILED` : '\nAll extension checks passed.');
  process.exit(failed ? 1 : 0);
})();
