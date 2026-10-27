// Watches what chrome.tabs and chrome.windows show while a closed tab or Peek is parked (#380). The shell parks an
// engine copy of every page it closes; an extension must not see it, list it, reach it by id or hear of it.
// Driven over CDP (engine/tools/cdp.mjs, match type:service_worker):
//   self.parkedProbe.report().then((r) => { self.lastReport = JSON.stringify(r); })   then read self.lastReport.
const events = { created: [], removed: [], attached: [], detached: [], activated: [], updated: [] };

chrome.tabs.onCreated.addListener((tab) => events.created.push(tab.id));
chrome.tabs.onRemoved.addListener((tabId) => events.removed.push(tabId));
chrome.tabs.onAttached.addListener((tabId) => events.attached.push(tabId));
chrome.tabs.onDetached.addListener((tabId) => events.detached.push(tabId));
chrome.tabs.onActivated.addListener((info) => events.activated.push(info.tabId));
chrome.tabs.onUpdated.addListener((tabId) => events.updated.push(tabId));

// Keeps the worker (and its CDP target) alive between driven steps.
setInterval(() => chrome.runtime.getPlatformInfo(), 20000);

// Calls `call(id)` for every id in `ids` and answers the ones that did not fail: a tab an extension cannot see
// cannot be found by guessing either. Session ids come from one counter (tabs and windows alike), so a tab the
// engine made lately has an id close to the ones the extension is shown.
async function reachable(ids, call) {
  const found = [];
  for (const id of ids) {
    try {
      await call(id);
      found.push(id);
    } catch (error) {
      // not found: expected for ids that are not tabs the extension may see
    }
  }
  return found;
}

self.parkedProbe = {
  events,
  clearEvents() {
    for (const key of Object.keys(events)) events[key].length = 0;
  },
  // tabs.query count and ids, windows.getAll(populate) count and ids, and the ids that tabs.get, tabs.update and
  // tabs.reload can reach by guessing ids near the listed ones.
  async report() {
    const tabs = await chrome.tabs.query({});
    const windows = await chrome.windows.getAll({ populate: true, windowTypes: ["normal", "popup", "app", "devtools"] });
    const listed = tabs.map((tab) => tab.id).sort((a, b) => a - b);
    const populated = windows.flatMap((window) => (window.tabs || []).map((tab) => tab.id)).sort((a, b) => a - b);
    const known = [...listed, ...windows.map((window) => window.id)];
    const ids = [];
    for (let id = Math.min(...known) - 30; id <= Math.max(...known) + 60; id++) ids.push(id);
    // update and reload skip the tabs the query lists, so the probe never disturbs a real tab.
    const guessed = ids.filter((id) => !listed.includes(id));
    const got = await reachable(ids, (id) => chrome.tabs.get(id));
    const updated = await reachable(guessed, (id) => chrome.tabs.update(id, { muted: false }));
    const reloaded = await reachable(guessed, (id) => chrome.tabs.reload(id));
    return {
      queryCount: tabs.length,
      queryIds: listed,
      windowCount: windows.length,
      populatedIds: populated,
      reachableByGet: got,
      reachableByUpdate: updated,
      reachableByReload: reloaded,
      created: events.created.length,
      removed: events.removed.length,
      attached: events.attached.length,
      detached: events.detached.length,
      activated: events.activated.length,
    };
  },
};
