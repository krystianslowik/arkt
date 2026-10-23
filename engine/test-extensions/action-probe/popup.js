document.getElementById("create").addEventListener("click", () => {
  chrome.tabs.create({ url: "about:blank#probe-create", active: false });
});
document.getElementById("open").addEventListener("click", () => {
  window.open("about:blank#probe-open");
});
document.getElementById("window").addEventListener("click", () => {
  chrome.windows.create({ url: "about:blank#probe-window" });
});
