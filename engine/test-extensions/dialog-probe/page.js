// Each call returns at once; the answer lands in window.lastResult, so a CDP
// evaluate does not wait for the prompt.
window.lastResult = "none";

function requestPermissions() {
  window.lastResult = "pending";
  chrome.permissions
    .request({
      permissions: ["bookmarks", "history"],
      origins: ["https://example.com/*"],
    })
    .then((granted) => (window.lastResult = "granted=" + granted))
    .catch((e) => (window.lastResult = "error=" + e.message));
  return "requested";
}

function uninstall() {
  window.lastResult = "pending";
  chrome.management
    .uninstallSelf({ showConfirmDialog: true })
    .then(() => (window.lastResult = "uninstalled"))
    .catch((e) => (window.lastResult = "error=" + e.message));
  return "requested";
}
