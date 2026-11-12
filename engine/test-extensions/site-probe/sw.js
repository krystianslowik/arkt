// Counts completed tab loads on the action's badge, so a badge update reaches
// the listing, and disables the action on a page whose path holds "disabled",
// so a click shows the action's context menu instead (#593). The URL is
// readable while the probe has access to the site.
let loads = 0;
chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if (info.status !== "complete") return;
  loads += 1;
  chrome.action.setBadgeText({ text: String(loads) });
  if (tab.url && new URL(tab.url).pathname.includes("disabled")) {
    chrome.action.disable(tabId);
  } else {
    chrome.action.enable(tabId);
  }
});
