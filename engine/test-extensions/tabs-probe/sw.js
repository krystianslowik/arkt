chrome.tabs.query({}, (tabs) => {
  console.log("ARKT tabs.query count=" + tabs.length + " active=" + tabs.filter((t) => t.active).length);
});

// Keeps the worker (and its CDP target) alive between driven steps.
setInterval(() => chrome.runtime.getPlatformInfo(), 20000);
