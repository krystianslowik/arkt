chrome.tabs.query({}, (tabs) => {
  console.log("ARKT tabs.query count=" + tabs.length + " active=" + tabs.filter((t) => t.active).length);
});
