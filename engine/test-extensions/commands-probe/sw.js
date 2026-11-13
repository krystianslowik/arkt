// The #598 smoke reads what this records: every chrome.commands.onCommand
// (the command, the tab id and URL it came with) and every popup opening
// (popup.js), in storage.local, counted on the badge.
//
// From DevTools on this service worker:
//   reset()     clear the records
//   records()   the records, oldest first

async function add(record) {
  const { records = [] } = await chrome.storage.local.get("records");
  records.push({ ...record, at: Date.now() });
  await chrome.storage.local.set({ records });
  await chrome.action.setBadgeText({ text: String(records.length) });
}

chrome.commands.onCommand.addListener((command, tab) => {
  add({ kind: "command", command, tabId: tab ? tab.id : null, url: tab ? tab.url : null });
});

chrome.runtime.onMessage.addListener((message) => {
  if (message && message.kind === "popup") {
    add({ kind: "popup" });
  }
});

async function reset() {
  await chrome.storage.local.set({ records: [] });
  await chrome.action.setBadgeText({ text: "" });
  return "reset";
}

async function records() {
  const { records = [] } = await chrome.storage.local.get("records");
  return records;
}

self.reset = reset;
self.records = records;
