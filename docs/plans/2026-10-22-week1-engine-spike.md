# Week-1 Engine Spike (go/no-go) Implementation Plan

> Implement this plan task-by-task, with a review checkpoint after each task.

**Goal:** Prove, within one week, that our own Chromium 156 build can host a native AppKit/Swift UI in-process, show
page content inside our own AppKit layout at 120 Hz, and run Chrome extensions, which is the go/no-go for the
2026-12-22 beta.

**Architecture:** (engine research notes, section 9.7):
Chromium's `chrome_framework` loaded in-process by our
executable; our code runs inside the browser process via a `ChromeBrowserMainExtraParts` hook; page content is
the `WebContents` NSView reparented into our AppKit hierarchy. For the spike, Chrome's `BrowserView` stays the
window owner (v0 hybrid from section 9.6); the native `BrowserWindow` implementation is week 2+.

**Tech Stack:** Chromium 156.0.8078.48 (GN + Siso), ObjC++ for the bridge, Swift 6 / AppKit, Xcode 27.1
(SDK 27.0), git `format-patch`/`am -3` for the patch set.

**Paths used throughout**

| Name | Path |
|---|---|
| `$REPO` | root of this git repo |
| `$CR` | `$CHROMIUM_ROOT/chromium/src` (Chromium checkout, pinned to 156.0.8078.48) |
| `$OUT` | `$CR/out/Spike` |
| depot_tools | `$CHROMIUM_ROOT/depot_tools` (prepend to `PATH` in every shell) |

**Rules**
- Never touch anything on the Chromium disk outside `$CHROMIUM_ROOT`.
- Our own engine code lives in `$REPO/engine/arkt/` and is symlinked to `$CR/arkt`. Upstream edits exist only as
  patch files in `$REPO/engine/patches/chromium/` listed in `.patches` (order file).
- Chromium class and function names below are from the engine research notes and may have churned at milestone 156.
  Before editing any upstream file, confirm the symbol with `git -C $CR grep -n '<symbol>'` and adapt.
- Time-box: if Task 4 or Task 6 is not working by end of day 4, stop and record NO-GO with the failure in Task 9.

---

### Task 1: Baseline build of stock Chromium 156

Proves the toolchain (Xcode 27.1 / SDK 27.0 vs. what Chromium 156 expects) before we change anything.

**Files:**
- Create: `$OUT/args.gn`

**Step 1: Confirm the checkout is clean on the pin**

Run:
```zsh
export PATH=$CHROMIUM_ROOT/depot_tools:$PATH
cd $CHROMIUM_ROOT/chromium/src
git describe --tags && git status --short | wc -l
```
Expected: `156.0.8078.48` and `0` (if not 0, rerun `gclient sync -D --no-history --with_tags -j 4` from the
parent dir, then `gclient runhooks`).

**Step 2: Write build args**

`$OUT/args.gn`:
```gn
is_debug = false
is_component_build = true
symbol_level = 0
blink_symbol_level = 0
v8_symbol_level = 0
dcheck_always_on = false
target_cpu = "arm64"
use_siso = true
```
Component build keeps relinks fast while iterating; the release framework (week 7) uses `is_component_build = false`.

**Step 3: Generate and build**

Run (in background, takes hours; log to file):
```zsh
gn gen out/Spike && time autoninja -C out/Spike chrome > $CHROMIUM_ROOT/build-spike.log 2>&1
```
Expected: ends with no `FAILED:` lines; `out/Spike/Chromium.app` exists.
If it fails on the SDK: record the exact error, then check `build/config/mac/mac_sdk.gni` for
`mac_sdk_official_version` and whether `mac_sdk_path` / `use_system_xcode` needs setting. Do not install other
Xcode versions without asking the user.

**Step 4: Smoke test**

Run: `open $OUT/Chromium.app --args --user-data-dir=/tmp/arkt-spike-profile chrome://version`
Expected: window opens and shows `156.0.8078.48`. Quit it.

**Step 5: Record**

Append build time, peak disk (`du -sh $OUT`) and any toolchain fixes to `$REPO/docs/plans/2026-10-22-week1-results.md`
(create it), then:
```zsh
cd $REPO && git add docs/plans/2026-10-22-week1-results.md && git commit -m "Record Chromium 156 baseline build"
```

---

### Task 2: Engine overlay and patch workflow

**Files:**
- Create: `$REPO/engine/arkt/BUILD.gn`
- Create: `$REPO/engine/patches/chromium/.patches` (empty file)
- Create: `$REPO/engine/README.md`
- Symlink: `$CR/arkt -> $REPO/engine/arkt`

**Step 1: Create the overlay and link it**

```zsh
mkdir -p $REPO/engine/arkt $REPO/engine/patches/chromium
: > $REPO/engine/patches/chromium/.patches
ln -s $REPO/engine/arkt $CR/arkt
```

`$REPO/engine/arkt/BUILD.gn`:
```gn
# Arkt engine overlay. Everything Arkt-specific inside Chromium lives here.
group("arkt") {
  deps = []
}
```

**Step 2: Document the patch loop in `engine/README.md`**

```markdown
# Arkt engine

- `arkt/` is symlinked into the Chromium checkout as `src/arkt`. Our own sources only.
- `patches/chromium/*.patch` are the only upstream edits, applied in the order listed in `.patches`.

Apply (fresh checkout at the pinned tag):
    cd $CR && git checkout -b arkt 156.0.8078.48
    for p in $(cat $REPO/engine/patches/chromium/.patches); do git am -3 $REPO/engine/patches/chromium/$p; done

Export after editing upstream files (one commit per patch on branch `arkt`):
    cd $CR && git format-patch --no-numbered --zero-commit --no-signature -o $REPO/engine/patches/chromium 156.0.8078.48..arkt
    ls $REPO/engine/patches/chromium/*.patch | xargs -n1 basename > $REPO/engine/patches/chromium/.patches
```

**Step 3: Create the working branch in Chromium**

```zsh
cd $CR && git checkout -b arkt
```
Expected: `Switched to a new branch 'arkt'`.

**Step 4: Commit**

```zsh
cd $REPO && git add engine && git commit -m "Add engine overlay and patch workflow"
```

---

### Task 3: Run our code inside the browser process

Goal: an ObjC++ hook in `src/arkt` runs after browser startup and logs, proving we can execute in-process.

**Files:**
- Create: `$REPO/engine/arkt/browser/arkt_browser_main_extra_parts.h`
- Create: `$REPO/engine/arkt/browser/arkt_browser_main_extra_parts.mm`
- Modify (patch 0001): `$CR/chrome/browser/chrome_content_browser_client.cc` (where other
  `ChromeBrowserMainExtraParts` are added; find with `git grep -n "AddParts(" chrome/browser/chrome_content_browser_client.cc`)
- Modify (patch 0001): `$CR/chrome/browser/BUILD.gn` to depend on `//arkt/browser`
- Create: `$REPO/engine/arkt/browser/BUILD.gn`

**Step 1: Write the hook**

`arkt_browser_main_extra_parts.h`:
```cpp
#ifndef ARKT_BROWSER_ARKT_BROWSER_MAIN_EXTRA_PARTS_H_
#define ARKT_BROWSER_ARKT_BROWSER_MAIN_EXTRA_PARTS_H_

#include "chrome/browser/chrome_browser_main_extra_parts.h"

namespace arkt {

class ArktBrowserMainExtraParts : public ChromeBrowserMainExtraParts {
 public:
  ArktBrowserMainExtraParts();
  ~ArktBrowserMainExtraParts() override;

  // ChromeBrowserMainExtraParts:
  void PostBrowserStart() override;
};

}  // namespace arkt

#endif  // ARKT_BROWSER_ARKT_BROWSER_MAIN_EXTRA_PARTS_H_
```

`arkt_browser_main_extra_parts.mm`:
```objc
#include "arkt/browser/arkt_browser_main_extra_parts.h"

#include "base/logging.h"

namespace arkt {

ArktBrowserMainExtraParts::ArktBrowserMainExtraParts() = default;
ArktBrowserMainExtraParts::~ArktBrowserMainExtraParts() = default;

void ArktBrowserMainExtraParts::PostBrowserStart() {
  LOG(WARNING) << "ARKT: in-process hook alive";
}

}  // namespace arkt
```

`engine/arkt/browser/BUILD.gn`:
```gn
source_set("browser") {
  sources = [
    "arkt_browser_main_extra_parts.h",
    "arkt_browser_main_extra_parts.mm",
  ]
  deps = [
    "//base",
    "//chrome/browser:browser_process",
  ]
}
```
Confirm the right dep for `chrome_browser_main_extra_parts.h` with
`git grep -n "chrome_browser_main_extra_parts.h" chrome/browser/BUILD.gn` and use the target that lists it.

**Step 2: Register it (upstream edit)**

In `chrome_content_browser_client.cc`, next to the other `main_parts->AddParts(...)` calls on Mac:
```cpp
#if BUILDFLAG(IS_MAC)
  main_parts->AddParts(std::make_unique<arkt::ArktBrowserMainExtraParts>());
#endif
```
plus `#include "arkt/browser/arkt_browser_main_extra_parts.h"` and `"//arkt/browser"` in the matching deps
list in `chrome/browser/BUILD.gn` (if a dependency cycle error appears, move the dep to the `chrome/browser:browser`
target's `public_deps` or register from `chrome/browser/chrome_browser_main_mac.mm` instead).

**Step 3: Build and verify the log line**

```zsh
autoninja -C out/Spike chrome
$OUT/Chromium.app/Contents/MacOS/Chromium --user-data-dir=/tmp/arkt-spike-profile --enable-logging=stderr 2>&1 | grep -m1 "ARKT: in-process hook alive"
```
Expected: the line prints within a few seconds. Quit Chromium.

**Step 4: Export patch and commit**

```zsh
cd $CR && git add -A chrome && git commit -m "Arkt: register in-process browser hook"
git format-patch --no-numbered --zero-commit --no-signature -o $REPO/engine/patches/chromium 156.0.8078.48..arkt
ls $REPO/engine/patches/chromium/*.patch | xargs -n1 basename > $REPO/engine/patches/chromium/.patches
cd $REPO && git add engine && git commit -m "Run Arkt hook inside the Chromium browser process"
```

---

### Task 4: Page content inside our own AppKit layout

Goal: our code takes the active tab's `WebContents` NSView, mounts it into our own AppKit container (sidebar
placeholder + inset rounded card) inside a window we create, and input works.

**Files:**
- Create: `$REPO/engine/arkt/browser/arkt_window_controller.h`
- Create: `$REPO/engine/arkt/browser/arkt_window_controller.mm`
- Modify: `$REPO/engine/arkt/browser/arkt_browser_main_extra_parts.mm`
- Modify: `$REPO/engine/arkt/browser/BUILD.gn` (add sources, deps `//chrome/browser/ui`, `//content/public/browser`)

**Step 1: Implement the controller**

`arkt_window_controller.h`:
```objc
#ifndef ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_
#define ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_

#import <AppKit/AppKit.h>

namespace content {
class WebContents;
}

// Hosts one WebContents NSView inside an Arkt-owned layout: a 190 pt sidebar
// placeholder and an inset, rounded content card.
@interface ArktWindowController : NSWindowController
- (instancetype)initWithWebContents:(content::WebContents*)webContents;
@end

#endif  // ARKT_BROWSER_ARKT_WINDOW_CONTROLLER_H_
```

`arkt_window_controller.mm`:
```objc
#import "arkt/browser/arkt_window_controller.h"

#include "content/public/browser/web_contents.h"

namespace {
constexpr CGFloat kSidebarWidth = 190;
constexpr CGFloat kCardInset = 10;
constexpr CGFloat kCardRadius = 10;
}  // namespace

@implementation ArktWindowController {
  content::WebContents* _webContents;  // Not owned; the tab strip owns it.
  NSView* _card;
}

- (instancetype)initWithWebContents:(content::WebContents*)webContents {
  NSWindow* window = [[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 1400, 900)
                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskFullSizeContentView
                  backing:NSBackingStoreBuffered
                    defer:NO];
  window.titlebarAppearsTransparent = YES;
  window.titleVisibility = NSWindowTitleHidden;
  if ((self = [super initWithWindow:window])) {
    _webContents = webContents;
    [self buildLayout];
  }
  return self;
}

- (void)buildLayout {
  NSView* root = self.window.contentView;
  root.wantsLayer = YES;
  root.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;

  _card = [[NSView alloc] initWithFrame:NSZeroRect];
  _card.wantsLayer = YES;
  _card.layer.cornerRadius = kCardRadius;
  _card.layer.masksToBounds = YES;
  _card.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:_card];

  NSView* page = _webContents->GetNativeView().GetNativeNSView();
  [page removeFromSuperview];
  page.translatesAutoresizingMaskIntoConstraints = NO;
  [_card addSubview:page];

  [NSLayoutConstraint activateConstraints:@[
    [_card.leadingAnchor constraintEqualToAnchor:root.leadingAnchor
                                        constant:kSidebarWidth],
    [_card.trailingAnchor constraintEqualToAnchor:root.trailingAnchor
                                         constant:-kCardInset],
    [_card.topAnchor constraintEqualToAnchor:root.topAnchor constant:kCardInset],
    [_card.bottomAnchor constraintEqualToAnchor:root.bottomAnchor
                                       constant:-kCardInset],
    [page.leadingAnchor constraintEqualToAnchor:_card.leadingAnchor],
    [page.trailingAnchor constraintEqualToAnchor:_card.trailingAnchor],
    [page.topAnchor constraintEqualToAnchor:_card.topAnchor],
    [page.bottomAnchor constraintEqualToAnchor:_card.bottomAnchor],
  ]];
}

@end
```

**Step 2: Open it after startup**

In `PostBrowserStart()`, post a task (so the first browser window exists) that finds the last active browser
(`chrome::FindLastActive()` or `BrowserList::GetInstance()->GetLastActive()`, whichever exists in 156), takes
`browser->tab_strip_model()->GetActiveWebContents()`, creates `ArktWindowController`, keeps it alive in a static
`NSMutableArray`, and calls `showWindow:`. Hide Chrome's own window with `[browserNSWindow orderOut:nil]`
(get it from `browser->window()->GetNativeWindow().GetNativeNSWindow()`).

**Step 3: Verify manually**

Build, launch with `--user-data-dir=/tmp/arkt-spike-profile https://example.com`.
Expected:
- Our window shows the page inside the rounded card, 190 pt from the left.
- Clicking links navigates; typing in a page text field works; scrolling works; Cmd-C/Cmd-V work in the page.
- Resizing our window resizes the page.

Record each item as PASS/FAIL in `week1-results.md`. Focus/first-responder or keyboard failures are the main
risk (section 9.6 risk 1): if keys do not reach the page, try `[self.window makeFirstResponder:page]` and record.

**Step 4: Commit**

```zsh
cd $REPO && git add engine docs/plans/2026-10-22-week1-results.md && git commit -m "Host WebContents inside an Arkt AppKit layout"
```

---

### Task 5: 120 Hz animation of the page container

**Files:**
- Modify: `$REPO/engine/arkt/browser/arkt_window_controller.mm`

**Step 1: Add a frame-paced animation and measurement**

Add a method that, when the window receives Ctrl-Opt-A (local `NSEvent` monitor), slides `_card` 300 pt right
and back with a spring (`CASpringAnimation` on `transform.translation.x`, damping 1.0, response 0.35) while a
display link (`[self.window.contentView displayLinkWithTarget:selector:]`, macOS 14+) records frame timestamps
for 2 seconds, then logs:

```objc
LOG(WARNING) << "ARKT frames=" << count << " max_ms=" << maxIntervalMs
             << " over_8_6ms=" << slowFrames;
```

**Step 2: Verify**

Check the display first: `system_profiler SPDisplaysDataType | grep -i -E "refresh|promotion"`.
On a ProMotion display, trigger the animation 5 times with a page that is playing a video (YouTube) and once on a
static page. Expected (go criterion): `over_8_6ms` is at most 1% of `frames` and there is no visible tearing or
blank page during the slide. On a 60 Hz display, use 16.8 ms and note that 120 Hz could not be tested.

**Step 3: Record and commit**

```zsh
cd $REPO && git add engine docs/plans/2026-10-22-week1-results.md && git commit -m "Measure 120 Hz page container animation"
```

---

### Task 6: Extension install, action and popup

**Files:**
- Create: `$REPO/engine/arkt/browser/arkt_extensions_bridge.h`
- Create: `$REPO/engine/arkt/browser/arkt_extensions_bridge.mm`
- Modify: `$REPO/engine/arkt/browser/BUILD.gn`

**Step 1: Install uBlock Origin Lite with Chrome's default UI**

In our window, navigate to `https://chromewebstore.google.com/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh`
(load via `_webContents->GetController().LoadURLWithParams` or by typing in Chrome's hidden window before
reparenting). Click "Add to Chrome". The install prompt will be Chrome's Views dialog; accept it.
Expected: install succeeds; record PASS/FAIL. (Native install sheet via `ShowDialogCallback` is week 3, not a
go criterion.)

**Step 2: List extension actions from our code**

In `arkt_extensions_bridge.mm`, get `ToolbarActionsModel::Get(profile)` (confirm name with
`git grep -n "class ToolbarActionsModel" chrome/browser/ui`), and log each action id and title:
```objc
for (const auto& id : model->action_ids()) {
  LOG(WARNING) << "ARKT action " << id;
}
```
Expected: uBO Lite's id `ddkjiahejlhfcafbddmgiahcphecmpfh` is listed.

**Step 3: Show the popup in an NSPopover**

Find the per-action controller (`git grep -n "class ExtensionActionViewModel\|class ExtensionActionViewController" chrome/browser/ui`)
and trigger its popup. Locate the popup's `ExtensionViewHost` (`git grep -n "ExtensionViewHost" chrome/browser/ui/extensions`),
take its `host_contents()` NSView, and place it in an `NSPopover` anchored to a placeholder button in our sidebar.
Time-box this step to 1.5 days. Expected: the uBO Lite popup renders and its toggle works.
If time runs out: record PARTIAL with what blocked it (Chrome's Views bubble still works as the v0 fallback).

**Step 4: Commit**

```zsh
cd $REPO && git add engine docs/plans/2026-10-22-week1-results.md && git commit -m "Bridge extension actions and popup into AppKit"
```

---

### Task 7: Extension APIs see our tabs

**Step 1: Load a test extension**

Create `$REPO/engine/test-extensions/tabs-probe/manifest.json`:
```json
{
  "manifest_version": 3,
  "name": "Arkt tabs probe",
  "version": "1.0",
  "permissions": ["tabs"],
  "background": { "service_worker": "sw.js" }
}
```
`$REPO/engine/test-extensions/tabs-probe/sw.js`:
```js
chrome.tabs.query({}, (tabs) => {
  console.log("ARKT tabs.query count=" + tabs.length + " active=" + tabs.filter((t) => t.active).length);
});
```
Launch with `--load-extension=$REPO/engine/test-extensions/tabs-probe` and inspect the service worker console via
`chrome://extensions` (Developer mode, "service worker" link).

**Step 2: Verify**

Expected: `count` equals the number of tabs open (including the one shown in our window), `active=1` per window.

**Step 3: Commit**

```zsh
cd $REPO && git add engine/test-extensions docs/plans/2026-10-22-week1-results.md && git commit -m "Verify chrome.tabs sees Arkt-hosted tabs"
```

---

### Task 8: 1Password desktop integration (MUST HAVE, go criterion)

Password-manager extensions (1Password) are a must-have. 1Password's desktop app only talks to browsers
whose code signature it trusts, so this task includes signing the spike build.

**Step 1:** Install the 1Password extension from the Web Store in the spike build.

**Step 2:** Sign the spike app bundle (Developer ID if available, otherwise Apple Development) including
helpers and the framework, then verify:
```zsh
codesign --force --deep --options runtime --sign "<identity>" $OUT/Chromium.app
codesign --verify --deep --strict --verbose=2 $OUT/Chromium.app
```
Expected: `valid on disk` and `satisfies its Designated Requirement`. (`--deep` is acceptable for the spike only;
release signing signs each nested bundle explicitly.)

**Step 3:** In 1Password desktop, Settings > Browser, add `$OUT/Chromium.app` as an additional browser
(confirm the current menu wording in 1Password's support docs if it differs).

**Step 4: Verify:** the extension shows it is connected to the desktop app and unlocks with Touch ID / the
desktop app. Record PASS / FAIL with the exact message shown. If it fails, capture 1Password's log
(`~/Library/Group Containers/2BUA8C4S2C.com.1password/Library/Application Support/1Password/Data/logs`) lines
that mention the browser, without copying any vault data.

**Step 4: Commit** the results file.

---

### Task 9: Go/no-go decision

**Files:**
- Modify: `$REPO/docs/plans/2026-10-22-week1-results.md`

**Step 1:** Fill in the table:

| Criterion | Required for GO | Result |
|---|---|---|
| Baseline build (Task 1) | yes | |
| In-process hook (Task 3) | yes | |
| Page in our AppKit layout, input works (Task 4) | yes | |
| 120 Hz container animation, at most 1% slow frames (Task 5) | yes | |
| uBO Lite installs and popup works, native or Views fallback (Task 6) | yes | |
| chrome.tabs sees our tabs (Task 7) | yes | |
| 1Password extension connects to the desktop app (Task 8) | yes | |

**Step 2:** GO if every required row passes. Otherwise NO-GO: list the blocker and the fallback from engine
options section 9.7 ("CEF fallback") or 9.6 risk 1 (Views-hosted native sidebar).

**Step 3: Commit**

```zsh
cd $REPO && git add docs/plans/2026-10-22-week1-results.md && git commit -m "Week-1 engine spike go/no-go"
```
