// The action context items the #915 smoke checks: a normal item, a checkbox,
// a radio group, a submenu with a separator, an enabled and a disabled child
// and a title with "&&" (a literal "&" in Chrome's Mac menus), and a hidden
// item. Five visible top-level items: Chromium shows at most six
// (ACTION_MENU_TOP_LEVEL_LIMIT). Every click is kept in storage (`clicks`) with the
// values chrome.contextMenus.onClicked gives, and counted on the badge.
//
// From DevTools on this service worker:
//   reset()             recreate the items and clear the clicks
//   clicks()            the recorded clicks
//   chrome.contextMenus.update / create / remove as usual

const ITEMS = [
  { id: "run", title: "Run Probe" },
  { id: "follow", title: "Follow This Site", type: "checkbox", checked: true },
  { id: "mode-a", title: "Mode A", type: "radio", checked: true },
  { id: "mode-b", title: "Mode B", type: "radio" },
  { id: "more", title: "More" },
  { id: "more-one", parentId: "more", title: "Child One" },
  { id: "more-sep", parentId: "more", type: "separator" },
  { id: "more-save", parentId: "more", title: "Save && Share" },
  { id: "more-off", parentId: "more", title: "Child Off", enabled: false },
  { id: "hidden", title: "Hidden Item", visible: false },
];

function create(item) {
  return new Promise((resolve) => {
    chrome.contextMenus.create({ contexts: ["action"], ...item }, () => {
      resolve(chrome.runtime.lastError ? chrome.runtime.lastError.message : "ok");
    });
  });
}

async function reset() {
  await chrome.contextMenus.removeAll();
  const results = [];
  for (const item of ITEMS) {
    results.push(`${item.id}:${await create(item)}`);
  }
  await chrome.storage.local.set({ clicks: [] });
  await chrome.action.setBadgeText({ text: "" });
  return results.join(",");
}

async function clicks() {
  const { clicks = [] } = await chrome.storage.local.get("clicks");
  return clicks;
}

chrome.runtime.onInstalled.addListener(() => {
  reset();
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  const list = await clicks();
  list.push({
    menuItemId: info.menuItemId,
    parentMenuItemId: info.parentMenuItemId ?? null,
    checked: info.checked ?? null,
    wasChecked: info.wasChecked ?? null,
    tabId: tab ? tab.id : null,
    tabUrl: tab ? tab.url ?? null : null,
    pageUrl: info.pageUrl ?? null,
  });
  await chrome.storage.local.set({ clicks: list });
  await chrome.action.setBadgeText({ text: String(list.length) });
});

self.reset = reset;
self.clicks = clicks;
