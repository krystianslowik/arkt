// Tells the service worker this popup opened (#598).
chrome.runtime.sendMessage({ kind: "popup" });
