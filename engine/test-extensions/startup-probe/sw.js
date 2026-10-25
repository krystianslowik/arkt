// Opens a window once per browser session, as an extension that restores its own window at startup would (W3-9
// startup check). runtime.onStartup does not reach an extension loaded with --load-extension (it is installed again
// at every launch), so the first service worker start of the session does the same: storage.session is empty then.
// The page comes from the loopback fixture server on 127.0.0.1:8691.
const url = "http://127.0.0.1:8691/p/StartupProbe";

async function openOncePerSession(trigger) {
  const { opened } = await chrome.storage.session.get("opened");
  if (opened) return;
  await chrome.storage.session.set({ opened: true });
  const created = await chrome.windows.create({ url });
  console.log("ARKT startup-probe " + trigger + " window " + created.id);
}

chrome.runtime.onStartup.addListener(() => openOncePerSession("onStartup"));
openOncePerSession("first worker start");
