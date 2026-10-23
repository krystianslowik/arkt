console.log("ARKT action-probe sw ready");

// Driven over CDP. Service workers have no window.open, so `open` uses
// chrome.tabs.create with active: true; the popup button is the real
// window.open test.
self.probe = {
  create: () => chrome.tabs.create({ url: "about:blank#probe-create", active: false }),
  open: () => chrome.tabs.create({ url: "about:blank#probe-open", active: true }),
  window: () => chrome.windows.create({ url: "about:blank#probe-window" }),
};

// Keeps the worker (and its CDP target) alive between driven steps.
setInterval(() => chrome.runtime.getPlatformInfo(), 20000);
