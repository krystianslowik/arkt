# Engine week 2 results

Plan: `docs/plans/2026-10-23-engine-week2.md`. Variables (`$REPO`, `$CR`, `$OUT`, `$REL`, `$PROF`) as in the plan's
Rules. `$REPO` is the engine worktree `arkt-wt/engine` on branch `engine-week2`.

## Tasks

| Task | Title | Status | Notes |
|---|---|---|---|
| W0 | Branch, baselines, results file, CDP helper, key-window log | DONE | see below |
| W1 | Arkt-branded non-component build | TODO | |
| W2 | Sign `Arkt.app`, install in /Applications, smoke | TODO | |
| W3 | Inventory of non-`BrowserView` window seams, variant decision | TODO | |
| W4 | Extensions menu lists every action (finding 1) | TODO | |
| W5a | `ArktBrowserWindow` skeleton behind `--arkt-native-window` | TODO | |
| W5b | Seam fixes found by the smoke matrix (GATE) | TODO | |
| W5c | Arkt-owned tab list and visibility (finding 2) | TODO | |
| W6 | Extension window identity, extension-created tabs and windows (finding 3) | TODO | |
| W7 | Web Store install on the native window | TODO | |
| W8 | Keychain: mock in tests, "Arkt Safe Storage" in the product (finding 5) | TODO | |
| W9 | Native window as default; try dropping patch 0002 | TODO | |
| W10 | Release bundle rebuild, re-sign, final smoke, housekeeping | TODO | |
| WE | Embedding spike (lane C) | TODO | |

## Patch budget (design target: fewer than 30 patch files)

| # | Patch | Status | Upstream files | Hunks in hot files |
|---|---|---|---|---|
| 0001 | Register in-process browser hook | exists | 2 | 0 |
| 0002 | Let a WebContents view draw again after leaving Views | exists; W9 tries to drop it | 4 | 0 |
| 0003 | `BrowserWindow` factory hook for Arkt (W5a) | new | 2 (`browser_window_factory.cc`, `frame/BUILD.gn`) | 0 |
| 0004+ | Non-`BrowserView` normal window seams (W5b), grouped by theme | new, measured in W3/W5b | W3 estimate | W3 estimate |
| next | Arkt keychain item name (W8) | new | 1 | 0 |

Current totals: 2 patch files, 6 upstream files, 0 hot-file hunks.

## W0

Date 2026-10-23.

### Step 1: worktree, symlink, patch count

- Worktree `arkt-wt/engine`, branch `engine-week2`, created from `main` at `2cbedaa` (the public repo has no
  `spike/week1` branch; `main` carries the week-1 overlay and patches).
- Old `$CR/arkt` target: the `engine/arkt` directory of a different checkout of this repository (not a worktree of
  it). Its overlay and patch contents were identical to `main`'s apart from the patch `From:` header.
- `readlink $CR/arkt` now prints `$REPO/engine/arkt` (expanded).
- `git -C $CR branch --show-current`: `arkt`
- `git -C $CR rev-list --count 156.0.8078.48..arkt`: `2`
- `wc -l < $REPO/engine/patches/chromium/.patches`: `2`
- Hot-file hunks (patch budget command): `0`
- Upstream files touched by `156.0.8078.48..arkt` (`git diff --stat`): 6
  (`chrome/browser/BUILD.gn`, `chrome/browser/chrome_browser_main.cc` for 0001;
  `render_widget_host_ns_view_bridge.{h,mm}`, `render_widget_host_view_mac.mm`, `render_widget_host_ns_view.mojom`
  for 0002).

### Step 2: key-window log

`ArktWindowController` observes `NSWindowDidBecomeKeyNotification` for its window and logs
`ARKT: key window <n>`; `showWindow:` logs `ARKT: window number <n>` on its own line.

### Step 3: CDP helper

`engine/tools/cdp.mjs`, no dependencies (Node global `fetch` and `WebSocket`, checked with Node 26.10).

### Step 4: build and baseline run

Build: `nice -n 15 autoninja -C out/Spike chrome`: `The build has finished successfully.`, 0 `FAILED:` lines.

Launch with the plan's command (profile `$PROF/week2`, `--use-mock-keychain`, `--remote-debugging-port=9333`,
`--load-extension=$REPO/engine/test-extensions/tabs-probe`, page `manifest.json`).

```
ARKT: window number 37611
ARKT: mounted active tab after 1 attempt(s)
ARKT: key window 37611
```

| Command | Output | Exit |
|---|---|---|
| `cdp.mjs manifest.json 'document.visibilityState'` | `"visible"` | 0 |
| `cdp.mjs manifest.json 'navigator.userActivation.isActive'` | `false` | 0 |
| `cdp.mjs --user-gesture manifest.json 'navigator.userActivation.isActive'` | `true` | 0 |
| `cdp.mjs manifest.json 'nope.x'` | `cdp: ReferenceError: nope is not defined` | 1 |
| `cdp.mjs manifest.json 'Promise.reject(new Error("boom"))'` | `cdp: Error: boom` | 1 |
| `cdp.mjs nomatch '1'` | `cdp: no target matches "nomatch"` plus the target list | 1 |
| `cdp.mjs --navigate manifest.json 'about:blank'` | `{"frameId":...,"loaderId":...,"isDownload":false}`; then `cdp.mjs about:blank 'location.href'` prints `"about:blank"` | 0 |
| `cdp.mjs --navigate about:blank 'notascheme'` | `cdp: Cannot navigate to invalid URL` | 1 |
| `cdp.mjs --port 9399 x '1'` (nothing listening) | `cdp: cannot read /json/list on port 9399: fetch failed` | 1 |

`type:service_worker` matched a component extension's worker (`"Contextual Tasks"`), not the probe: this confirms the
Rules' instruction to match workers by extension id.

The browser was stopped by its PID; no `$OUT/Chromium.app` processes were left.

### Machine state after W0

- `df -h /`: 15 GiB available (of 460 GiB).
- `sysctl vm.swapusage`: `total = 7168.00M  used = 5605.50M  free = 1562.50M`.
- Load average 14.01 9.08 7.32.
