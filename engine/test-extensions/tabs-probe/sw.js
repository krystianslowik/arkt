chrome.tabs.query({}, (tabs) => {
  console.log("ARKT tabs.query count=" + tabs.length + " active=" + tabs.filter((t) => t.active).length);
  console.log("ARKT tabs.query windows=" + [...new Set(tabs.map((t) => t.windowId))].join(","));
});

// Keeps the worker (and its CDP target) alive between driven steps.
setInterval(() => chrome.runtime.getPlatformInfo(), 20000);

// Runs chrome.windows.remove from the worker for the probe's control page (#401). The engine tells an extension's
// window close by the call's keepalive, which a worker call holds and an extension page's call does not.
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.arktRemoveWindow === undefined) return false;
  chrome.windows.remove(message.arktRemoveWindow).then(
    () => sendResponse("ok"),
    (error) => sendResponse("error " + error.message));
  return true;
});
