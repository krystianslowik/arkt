# Arkt - design

Date: 2026-10-22. Status: approved (sections 1-5).

Arkt is a native macOS browser that rebuilds Arc's experience 1:1 after The Browser Company sunsets Arc on
2026-12-22. Clean-room: Arc's behavior is studied from the outside, never copied. Own code, assets and brand.

## 0. Decisions

| Topic | Decision |
|---|---|
| Audience | Public product: signed, notarized, auto-updating |
| Team / timeline | Solo developer; usable beta for Arc refugees around 2026-12-22 |
| UI | As native as possible; "smooth af" = 120 Hz on hot paths |
| v1 scope | Sidebar + Spaces, command bar, split view + Little Arkt, auto-archive + Peek, Arc import |
| Parity | Shortcuts and behaviors 1:1 with Arc 1.168.0, per `docs/spec/arc-parity-spec.md` |
| Extensions | Full Chrome extension support is mandatory (Web Store, password managers) |
| Engine | Our own Chromium build compiled as a framework with our own ObjC/Swift API. Not WKWebView, not CEF |
| Chromium pin | 156.0.8078.48 (Stable + Extended) through launch, then rebase per milestone |
| Build host | One Mac, Chromium source and output under `$CHROMIUM_ROOT` (see `engine/README.md`) |

## 1. Architecture

```
Arkt.app  (Swift; AppKit for hot paths, SwiftUI for dialogs)
├─ App layer: TCA reducers per feature (sidebar, spaces, command bar,
│   split view, little arkt, peek, archive, import)
├─ EngineClient: Swift protocol, the only thing the UI talks to
│   └─ ChromiumEngine: Swift wrapper over ArktCore
└─ Frameworks/ArktCore.framework  (our Chromium build)
     ├─ Chromium chrome_framework target, renamed
     ├─ src/arkt/: ObjC++ API (ArktBrowserApplication, ArktBrowserContext per
     │   profile, ArktWebContents per tab, extensions, autocomplete,
     │   downloads, passwords)
     ├─ ArktBrowserWindow: AppKit implementation of BrowserWindow
     └─ < 30 upstream patches, Brave-style overlay, Electron patch tooling
```

- One engine boundary: UI never touches Chromium directly. Reducers are testable and the engine is swappable.
- Native everywhere: sidebar, command bar, extension icons and popups, permission prompts, install sheets are
  AppKit. Chromium views are used only for page content (`WebContentsViewCocoa` inside our hierarchy).
- Smoothness rules: hot paths in AppKit + Core Animation; custom spring driver; Metal Space theme; nothing blocks
  the main thread during animation.
- Extensions: Chromium's extension system unchanged. `ToolbarActionsModel` drives natively drawn action icons;
  popups arrive as `ExtensionViewHost` WebContents shown in our own popover; `ExtensionInstallPrompt`'s
  `ShowDialogCallback` drives native install sheets.

## 2. Sidebar, Spaces, command bar

**Window**: borderless `NSWindow`, traffic lights in the sidebar, content in an inset card (9-10 pt inset,
8-10 pt radius, hairline border) over the Space's Metal theme.

**Sidebar** (~190 pt, resizable, hideable)
- Favorites: `NSCollectionView` grid, 3 per row, tiles ~52x46 pt, shared across Spaces, per profile.
- Pinned + Today: `NSOutlineView`, rows ~34 pt on a 41 pt pitch. Row states: current 85%, visible 70%,
  previous 32% opacity (Arc's token levels; our own values).
- Drag and drop: our own drag controller with spring-animated row reordering. Never SwiftUI lists.
- Bottom bar: archive, Space dots, "+".

**Spaces**: name, icon, theme (gradient stops, grain, light/dark), own pinned and Today trees, optional profile.
Two-finger swipe slides sidebars interactively and settles on a spring; the theme crossfades on the GPU in sync.
One tree with ordered child IDs, matching Arc's model so import is near 1:1.

**Command bar** (Cmd-T new tab, Cmd-L current tab): pre-warmed floating `NSPanel`, ~766 pt wide, a third of the
way down, dark surface; `NSTableView` with ~50 pt rows. Results from Chromium's autocomplete (history,
suggestions, open tabs, bookmarks) blended with tab switching, commands and Spaces. Must appear in < 16 ms.

**Theming**: tokens follow Arc's approach (black/white at low opacity over the theme); our own values and brand.

## 3. Split view, Little Arkt, Peek, auto-archive

- **Split view**: one sidebar item holding 2-4 panes, horizontal or vertical. Each pane is a Chromium tab. Created
  by dragging a tab to the page edge or Ctrl-Shift-=; closed with Ctrl-Shift--. Divider resizing drives
  Core Animation layer frames, not Auto Layout.
- **Little Arkt**: small borderless window for links from other apps and a global hotkey; one action: move into a
  Space or the main window. Its own archive threshold.
- **Peek**: cross-site links from Favorites and pinned tabs open in a floating panel over the page; dismiss or
  promote to a tab. Esc closes.
- **Auto-archive**: unpinned tabs idle past the threshold (1h, 6h, 12h default, 24h, 7d, 30d, never) move to the
  archive with reason, time, source and a full item snapshot. Restorable from the Library.

Exact rules and shortcuts come from `docs/spec/arc-parity-spec.md`, not from this summary.

## 4. Data, persistence, Arc import

**Stores** (local only, no account)
- Sidebar store: one tree (Spaces, folders, tabs, Favorites, splits) held in memory; debounced background
  persistence to SQLite via GRDB. The main thread never waits on disk.
- Archive store: archived items with reason, time, source and snapshot.
- Settings: typed, mirroring Arc's (archive threshold, Cmd-1..9 mode, link routing, Peek). App-level values in
  user defaults, the rest in SQLite.
- Chromium profile data (history, cookies, passwords, extensions, downloads) stays in Chromium's per-profile
  storage. One Arkt profile = one Chromium profile; Spaces reference a profile.

**State flow**: user action -> reducer -> store -> AppKit views via targeted diffs (no full reloads). Engine
events are batched per display frame before reaching reducers. Session restore saves window, Space, selected
tab and each tab's navigation history (from Chromium).

**Arc import** (v1, one-time, read-only)
1. Parse `StorableSidebar.json` (Codable flat `[key, value]` arrays, 2001-epoch timestamps) into our tree.
2. Load favicons from `SidebarItemsFaviconCache/<md5(itemID)>`.
3. Import passwords, cookies, history and extensions from Arc's Chromium profile with Chromium's importer.
4. Optionally import the archive and link-routing rules.

**Sync**: not in v1 (Arc used CloudKit + Firebase). Local-first now.

## 5. Error handling and testing

**Errors**
- Renderer crash or hang: only that tab shows a native crashed view with Reload; hung-page notice becomes a
  native sheet.
- GPU process crash: Chromium restarts it; logged; the window stays up.
- Store write failure: in-memory state stays the source of truth; retry with backoff; atomic writes (temp file +
  rename) and a rolling backup of the last 5 versions.
- Import: per-Space transactions; a bad item is skipped and reported, the rest imports. Arc files are never written.
- Crash reporting: opt-in, no URLs or titles.

**Testing**
1. Parity: every KB/BH/GS row in the parity spec becomes an automated accessibility-driven UI test. CI reports
   rows passing.
2. Smoothness: frame-time tests for Space swipe, sidebar scroll, command bar open, split resize. Fail if more than
   1% of frames exceed 8.6 ms (one 120 Hz frame is 8.33 ms, plus slack) or the command bar misses the earliest possible frame (its `show()` work must stay under 4 ms p95; total
   input-to-pixels is then bounded by the display's vsync, 8.3-16.7 ms at 120 Hz).
3. Reducers: TCA `TestStore` with a fake `EngineClient`.
4. Importer: synthetic `StorableSidebar.json` fixtures built from the documented schema.
5. Engine smoke (the week-1 go/no-go, kept for every Chromium rebase): framework launches from Swift; a page
   renders in our AppKit window at 120 Hz; uBlock Origin Lite installs from the Web Store and its popup opens
   natively; 1Password connects to its desktop app.

Rows marked NEEDS-RUNTIME-CHECK are verified by driving a fresh Arc in a separate macOS test user, which becomes
the reference for those tests.

## References

- `docs/spec/arc-parity-spec.md` - 1:1 behavior spec

The research notes behind this design (live UI measurements, design system, Arc's on-disk data model, engine
comparison, behavior catalogs) are kept private and are not part of this repository. Plans cite them by short
names such as "data-model 2.1", "design-system doc 1.7" or "arc-findings".
