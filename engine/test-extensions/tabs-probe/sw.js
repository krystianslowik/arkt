chrome.tabs.query({}, (tabs) => {
  console.log("ARKT tabs.query count=" + tabs.length + " active=" + tabs.filter((t) => t.active).length);
  console.log("ARKT tabs.query windows=" + [...new Set(tabs.map((t) => t.windowId))].join(","));
});

// Keeps the worker (and its CDP target) alive between driven steps.
setInterval(() => chrome.runtime.getPlatformInfo(), 20000);
