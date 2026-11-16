// Panda browser extension (Chrome, Arc, Brave, Edge and other Chromium browsers).
//
// This worker does no polling. It wakes up only when a tab's address changes, checks whether
// the address is Instagram or YouTube, and if so asks the Panda Mac app (through the native
// host) whether that tab should be closed. Settings live in the Mac app, so the toggles in
// the menu bar are the single source of truth. Page content is never read.

const HOST = 'com.neilsethia.panda';

let port = null;
let nextId = 1;
const pending = new Map();   // id -> resolve
const inFlight = new Set();  // tab ids currently being checked or closed
const queued = new Map();    // tab id -> newest address that arrived during a check
let lastHello = null;
let lastError = '';

function connect() {
  if (port) return port;
  try {
    const p = chrome.runtime.connectNative(HOST);
    p.onMessage.addListener(onHostMessage);
    p.onDisconnect.addListener(() => {
      lastError = (chrome.runtime.lastError && chrome.runtime.lastError.message) || '';
      if (port === p) port = null;
      lastHello = null;
      for (const resolve of pending.values()) resolve(null);
      pending.clear();
    });
    port = p;
    lastError = '';
    p.postMessage({ type: 'hello' });
  } catch (error) {
    lastError = String(error);
    port = null;
  }
  return port;
}

function onHostMessage(message) {
  if (!message) return;
  if (message.type === 'hello') {
    lastHello = message;
    return;
  }
  if (message.type === 'verdict') {
    const resolve = pending.get(message.id);
    if (resolve) {
      pending.delete(message.id);
      resolve(message);
    }
  }
}

function ask(payload) {
  return new Promise((resolve) => {
    const p = connect();
    if (!p) {
      resolve(null);
      return;
    }
    const id = nextId++;
    pending.set(id, resolve);
    try {
      p.postMessage({ ...payload, id });
    } catch (error) {
      pending.delete(id);
      resolve(null);
      return;
    }
    // Never leave a check hanging if the host goes quiet.
    setTimeout(() => {
      if (pending.has(id)) {
        pending.delete(id);
        resolve(null);
      }
    }, 3000);
  });
}

// Cheap first pass so ordinary browsing never even reaches the native host.
function isCandidate(url) {
  if (!url) return false;
  let host;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch (error) {
    return false;
  }
  return (
    host === 'instagram.com' ||
    host.endsWith('.instagram.com') ||
    host === 'youtube.com' ||
    host.endsWith('.youtube.com') ||
    host === 'youtu.be'
  );
}

async function geometryFor(tab) {
  try {
    const win = await chrome.windows.get(tab.windowId, { populate: true });
    const tabs = win.tabs || [];
    return {
      left: win.left,
      top: win.top,
      width: win.width,
      index: tab.index,
      count: tabs.length,
      pinned: tabs.filter((t) => t.pinned).length,
    };
  } catch (error) {
    return {};
  }
}

async function inspect(tabId, url) {
  if (!isCandidate(url)) return;
  if (inFlight.has(tabId)) {
    // A check is already running for this tab. Remember the newest address so it is
    // looked at as soon as the current check finishes.
    queued.set(tabId, url);
    return;
  }
  inFlight.add(tabId);
  try {
    let tab;
    try {
      tab = await chrome.tabs.get(tabId);
    } catch (error) {
      return;
    }
    const current = tab.url || tab.pendingUrl || url;
    if (!isCandidate(current)) return;

    const geometry = await geometryFor(tab);
    const verdict = await ask({ type: 'check', url: current, ...geometry });
    if (!verdict || !verdict.block) return;

    if (verdict.delayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, verdict.delayMs));
    }

    // The tab may have moved on while Panda was running over. Only close it if it is
    // still somewhere Panda cares about.
    let latest;
    try {
      latest = await chrome.tabs.get(tabId);
    } catch (error) {
      return;
    }
    const latestUrl = latest.url || latest.pendingUrl || '';
    if (!isCandidate(latestUrl)) return;
    if (latestUrl !== current) {
      const recheck = await ask({ type: 'check', url: latestUrl, ...geometry, recheck: true });
      if (!recheck || !recheck.block) return;
    }

    // Closing the only tab would close the whole window, so leave a fresh tab behind.
    try {
      const siblings = await chrome.tabs.query({ windowId: latest.windowId });
      if (siblings.length <= 1) {
        await chrome.tabs.create({ windowId: latest.windowId, active: true });
      }
    } catch (error) {
      // Not fatal. Carry on and close the tab.
    }

    try {
      await chrome.tabs.remove(tabId);
    } catch (error) {
      return;
    }
    const p = connect();
    if (p) {
      try {
        p.postMessage({ type: 'closed', kind: verdict.kind });
      } catch (error) {
        // The app will simply miss this count.
      }
    }
  } finally {
    inFlight.delete(tabId);
    const next = queued.get(tabId);
    if (next !== undefined) {
      queued.delete(tabId);
      inspect(tabId, next);
    }
  }
}

// A new address in any tab: typed, bookmarked, clicked, redirected.
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url) {
    inspect(tabId, changeInfo.url);
  } else if (changeInfo.status === 'loading' && tab && tab.url) {
    inspect(tabId, tab.url);
  }
});

// A brand new tab that already knows where it is going.
chrome.tabs.onCreated.addListener((tab) => {
  const url = tab.pendingUrl || tab.url;
  if (tab.id !== undefined && url) inspect(tab.id, url);
});

// Switching to a tab that was already open before protection was turned on.
chrome.tabs.onActivated.addListener(async ({ tabId }) => {
  try {
    const tab = await chrome.tabs.get(tabId);
    inspect(tabId, tab.url || tab.pendingUrl);
  } catch (error) {
    // Tab vanished.
  }
});

// YouTube is a single-page app: moving from a normal video to a Short changes the address
// without loading a new page. These two events catch that.
chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
  if (details.frameId === 0) inspect(details.tabId, details.url);
});
chrome.webNavigation.onCommitted.addListener((details) => {
  if (details.frameId === 0) inspect(details.tabId, details.url);
});

chrome.runtime.onStartup.addListener(() => connect());
chrome.runtime.onInstalled.addListener(() => connect());

// Status for the little popup.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message && message.type === 'status') {
    const p = connect();
    if (p) {
      try {
        p.postMessage({ type: 'hello' });
      } catch (error) {
        // Reported as not connected below.
      }
    }
    setTimeout(() => {
      sendResponse({
        connected: !!port,
        appRunning: !!(lastHello && lastHello.appRunning),
        error: lastError,
      });
    }, p ? 250 : 0);
    return true;
  }
  return false;
});

connect();
