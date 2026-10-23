# Split View Implementation Plan (issue #27)

> Implement this plan task by task, with a review checkpoint after each task. Each task is one branch and one pull
> request ("Part of #27"; the last one says "Fixes #27"). Open a sub-issue of #27 per task so every PR still maps to
> one issue (CONTRIBUTING.md).

**Goal.** A Split View is one sidebar item (a `split` node) holding 2 to 4 tab panes, laid out side by side or top to
bottom inside the content area. Each pane is one engine tab, created through `EngineClient` and engine-agnostic: today
it runs on FakeEngine (WKWebView) and later on ChromiumEngine (#33) with no shell change.
- **Create** a split with Ctrl-Shift-=, by dragging a sidebar tab onto the page, or by Opt-clicking the current tab.
- **Remove a pane** with Ctrl-Shift--. The pane leaves the split and its tab stays open.
- **Cmd-W** closes just the focused pane (user decision 4).
- **Resize** by dragging the gap between panes. The drag sets layer-backed view frames directly, never Auto Layout,
  and meets the 120 Hz frame-time gate.
- **Follow the focused pane:** the URL bar, the Toolbar, Cmd-L and Back/Forward/Reload all act on the focused pane.
- **Archive and restore** handle whole splits and single panes.

**Architecture.** Same three layers as Track E.
1. `app/ArktCore/SidebarModel` gains the split operations (`Sidebar+Split.swift`). They are pure and value-typed, and
   they keep `widthFactors` matched to the panes.
2. `ShellUI` gains:
   - a ShellUI mirror of the split layout (`SplitOrientation`, `SplitLayoutInfo`) carried on `SidebarNodeInfo.split`;
   - split write methods on `SidebarSource`;
   - pure layout math (`SplitLayout`, `SplitDropZone`, `SplitFocus`);
   - the views `SplitContainerView`, `SplitDividerView` and `SplitDropOverlayView`;
   - the window wiring, in a new `ShellWindowController+Split.swift` so it conflicts less with other work on the
     controller.
3. `CoreBridge` maps between the two vocabularies (`BridgeMapping`, `ModelSidebarSource`). The App target only adds
   menu items.

ShellUI still imports no ArktCore module, and only FakeEngine imports WebKit.

**Tech stack.** Unchanged from Track E: Swift 6.4 toolchain in Swift 6 language mode, macOS 15, Xcode 27.1 with
XcodeGen, SwiftPM, AppKit and Core Animation, Swift Testing for pure tests, XCTest (`ShellKitGUITests`) for window
tests. No new dependencies.

## Findings from the current code

Five facts about `main` shaped this plan:
- **Cmd-W on a split pane is already done.** User decision 4 of the Track E plan landed in #46: `Sidebar.removePane`
  and `Archiver.archive`, covered by `CloseTabTests`. S8 only adds tests on top.
- **Width factors can drift from the pane count.** Nothing enforces that `widthFactors.count` matches the number of
  panes. `addTab(in: .split)`, `insert` and the Arc import never touch the factors.
- **The shell cannot see split layout today.** `SidebarNodeInfo.split(id:)` carries no orientation or factors, and
  ShellUI may not import SidebarModel.
- **There is no drag and drop anywhere in the shell yet.** S7 builds the first drag source and drop target.
- **E5c and the hover close button are merged.** The Archive window (#4) landed in #49 and the row close button (#8)
  in #48, so S8 has no extra start condition and S6 wires the pane X.

---

## Rules (read before every task)

| Name | Path |
|---|---|
| `$REPO` | `/path/to/arkt-wt/split` (git worktree, one branch per task: `feat/27-s<N>-<slug>`) |
| `$APP` | `$REPO/app/ArktShell` |
| `$KIT` | `$APP/ShellKit` |
| `$CORE` | `$REPO/app/ArktCore` |
| `$DD` | `$APP/build` (xcodebuild `-derivedDataPath`, gitignored) |

- **Start condition.** `main` at or after #49. That includes #46 (E5b: `removePane`, Cmd-W on panes, `onTabHidden`),
  #48 (#8, hover close X on sidebar rows), which S6 builds on, and #49 (#4, E5c Archive window), which S8 builds on
  because it touches `AppSession`, `MainMenu` and the Archive window texts.
- **Shell.** Use zsh. Set the variables once per shell: `REPO=/path/to/arkt-wt/split; APP=$REPO/app/ArktShell;
  KIT=$APP/ShellKit; CORE=$REPO/app/ArktCore; DD=$APP/build`
- **Capacity.** Run every build and test with `nice -n 20` and two jobs. At most two Swift builds may run at once
  across all work; never two inside this plan.
- **Concurrency.** Swift 6 language mode with complete concurrency checking. No `@unchecked Sendable` and no
  `nonisolated(unsafe)` in production code.
- **Hot paths.** Pane frames, divider frames and the drop preview are set directly inside
  `CATransaction.setDisableActions(true)`, the same way `ShellRootView.layout()` and `ContentCardView.layout()` do it.
  No Auto Layout, no SwiftUI.
  - A divider drag never calls `SidebarSource` per frame. Each `mutate` runs a diff over every node, `onDidChange` and
    an autosave schedule, and emits a `.node(split)` that makes the outline reload the row.
  - The new factors are committed once, on mouse-up.
- **Layering is enforced by tests.** `IsolationTests` (`CoreIsolationTests`, `WebKitIsolationTests`) must pass at the
  end of every task.
  - ShellUI never imports `SidebarModel`, `Archive`, `ArcImport`, `Persistence` or `GRDB`.
  - Only `FakeEngineKit` imports WebKit.
- **Engine-agnostic.** The shell talks to panes only through `EngineClient`: `createTab`, `closeTab`, `navigate`,
  `reload`, `goBack`, `goForward`, `snapshot`, `contentView`, `observe`.
  - Pane focus is decided by the shell: a local mouse-down monitor plus `window.makeFirstResponder(contentView)`.
  - Do not add methods to `EngineClient` in this plan. If ChromiumEngine needs an explicit `focus(_:)`, that belongs
    to #33 together with an `EngineContract` rule.
- **Storage format stays at version 1.** `SplitItem` gets no new fields; a new field would need a version bump, a
  frozen fixture and a migration (see `SidebarStorageFormat`). The active pane is window state only.
- **Arc data.** Same as Track E. Never read or write the user's Arc directory. Synthetic fixtures only.
  NEEDS-RUNTIME-CHECK rows are checked by driving a fresh Arc in a separate macOS test user (design section 5); the
  user's real Arc data is never read.
- **No emojis** anywhere: code, comments, fixtures, commit messages.
- **TDD.** Write the test, run it and watch it fail (a compile error counts), implement, run it again, commit.
- **Commits.** Stage with explicit pathspecs (`git add <paths>`, never `-A` or `.`). Plain messages.
- **Parity markers.** Behavior inferred without a spec row is marked `[I]` in a comment. Behavior that still needs Arc
  measured is marked `PARITY(NEEDS-RUNTIME-CHECK <row>)`.
- **Test commands:**
  - Core: `cd $CORE && nice -n 20 swift test -j 2 2>&1 | tail -5`
  - ShellKit pure: `cd $KIT && nice -n 20 swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -5`
  - ShellKit GUI (needs a logged-in GUI session): `cd $KIT && nice -n 20 swift test -j 2 --filter ShellKitGUITests
    2>&1 | tail -5`
  - Isolation: `cd $KIT && nice -n 20 swift test -j 2 --filter IsolationTests 2>&1 | tail -3`
  - App: `cd $APP && xcodegen generate && nice -n 20 xcodebuild -project ArktShell.xcodeproj -scheme ArktShell
    -configuration Debug -derivedDataPath $DD -jobs 2 build 2>&1 | tail -3`
- **Test counts.** Expected counts are written as "baseline + N" against the S0 numbers.

## Parity IDs this plan implements (from `docs/spec/arc-parity-spec.md`)

BH-122 and BH-123 were listed under "Not in this track" in Track E. This plan owns them. BH-123 already behaves per
user decision 4.

| ID | Behavior here | Task |
|---|---|---|
| BH-115 | A split is one sidebar item that can sit in Pinned, Today, a folder or Favorites, and can be moved. Rename, share and the Favorites tile are deferred (see Deferred) | S1, S2, S6 |
| BH-116, CF-06 | Adding a 5th pane does nothing and shows the toast "Cannot Add New Pane" | S1, S2, S5, S7 |
| BH-117 (part) | Created by Ctrl-Shift-=, by dragging a sidebar tab onto the content, by Opt-clicking the current tab (GS-032), and by "Add Right/Left/Top/Bottom Split" menu items | S5, S6, S7 |
| BH-119 | A split created from a Pinned tab stays in Pinned (it takes the target tab's place) | S1 |
| BH-120 | Convert to Horizontal / Vertical Split View flips the orientation | S1, S5, S6 |
| BH-121 (part) | "Separate All Tabs" (context menu, Opt-click on the split row, GS-033); "Remove Tab from Split View" (pane row context menu; the pane row X from #8) | S1, S6 |
| BH-122, KB-071, CF-18 | Ctrl-Shift-- takes the focused pane out of the split without closing its tab; it lands right after the split [I] | S1, S5 |
| BH-123 | Cmd-W archives (Today) or closes (Pinned, Favorites) only the focused pane; the split shrinks (user decision 4, already built in #46) | S4, S8 |
| BH-124, KB-075 | "Expand Current Split" keeps the focused pane and separates the others; "Separate Page from Split View" (unbound) | S1, S5 |
| BH-125, KB-074, BH-101 (split clause) | With the Toolbar on, each pane shows its own URL. Cmd-L edits and navigates the focused pane | S4 |
| BH-128, KB-072, KB-073 | Ctrl-Shift-1...4 focus pane N; next / previous pane wraps around (keys per CF-16, NEEDS-RUNTIME-CHECK RT-06) | S3 (math), S5 |
| KB-070 | Ctrl-Shift-= adds a pane (maximum 4) | S5 |
| GS-011 | Dragging a tab onto the content splits it; the drop zone sets the side and orientation | S7 |
| GS-032 | Opt-click the current tab: duplicates it into a split | S6 |
| GS-033 | Opt-click a split row: separates it | S6 |
| BH-104 (caption) | The command bar shows "Switch to Split View" for open tabs that are split panes | S6 |
| Design section 5 (2) | Divider resize: no frame over 8.6 ms at 120 Hz | S3, S9 |

**Deferred.** Each item below is cited so nobody adds it by accident, and gets its own issue:
- GS-010 and BH-118: drop a tab onto another sidebar tab (left or right half). This needs sidebar drop-target
  infrastructure (reordering, drop indicators), which does not exist.
- BH-126: Mute per pane needs engine audio state; Share has no share support; Archive Below is out of scope as in
  Track E. "Duplicate split" is in S6.
- BH-127: Opt-click on the close button unsplits. It is behind the flag
  `optionClickSplitTabCloseButtonToUnsplitEnabled` (RT-22) and builds on the row close button from #8.
- BH-148: the Peek Split button belongs to #29.
- BH-190: a toast above the pane it concerns. Toasts stay centered on the content area [I].
- KB-064 (New Note in Split): left out by user decision. Multi-select "Open in Split View" needs sidebar multi-select.
  "+" > New Split needs a "+" menu.
- BH-115 extras: renaming a split and rendering a split as a Favorites tile. `FavoritesGridView` draws tabs only.

## Decisions fixed for this plan

1. **What orientation means.** `Orientation.horizontal` means the panes are laid out along the horizontal axis (side
   by side, vertical gaps); `.vertical` means top to bottom.
   - New splits default to side by side.
   - The importer keeps mapping Arc's `layoutOrientation` string 1:1. The only place that turns the stored value into
     an axis is `SplitLayout.axis(for:)`, so if Arc's word means the opposite, only that function and its tests
     change.
   - PARITY(NEEDS-RUNTIME-CHECK RT-31).
2. **Width factors.** `widthFactors[i]` is pane i's share of the split's main axis. The operations in S1 keep `count
   == panes` and `sum == 1`.
   - Adding a pane makes all shares equal [I] (RT-35).
   - Removing or separating a pane rescales the others proportionally, as `removePane` already does.
   - Reordering moves each factor with its pane.
   - `insert`, `addTab(in: .split)` and the Arc import keep their current behavior, so storage v1 fixtures and
     imported files load unchanged. The layout normalizes defensively (`SplitLayout.normalized(_:count:)`): if the
     count is wrong, all shares become equal; non-finite or non-positive values are replaced; the result is
     renormalized.
3. **Pane cap.** `Sidebar.maximumSplitPanes = 4` (CF-06).
   - Enforced by the new operations and by `move` into a `.split` location.
   - Not enforced by `insert` (decode, restore, import), so no stored or imported tree is ever refused.
   - The new `SidebarError` cases are safe to add: the only matches today are `catch is SidebarError` (importer) and
     `catch SidebarError.duplicateID`, with no exhaustive switch.
4. **Minimum pane size and the divider.**
   - Minimum pane length is 240 pt [I] (RT-33), applied in points by the UI; the model stores fractions only.
   - Dragging divider i resizes only panes i and i+1 [I] (RT-33).
   - Double-click equalizes all panes [I], mirroring `SidebarResizeHandle`.
   - If the bounds are too small for N times the minimum, all panes get equal shares.
   - The gap between pane cards equals `ShellMetrics.cardInsetRight` (10 pt) and is the divider's hit area.
     TODO(measure) (RT-37).
5. **Live versus committed.** While dragging, `SplitContainerView` holds `liveFactors` and sets frames directly;
   nothing goes to the source.
   - On mouse-up it calls `onCommitFactors(split, factors)` once, which becomes one `setSplitWidthFactors` mutation
     and one autosave.
   - Window resizes keep the factors and only recompute frames.
6. **One engine tab per pane, created lazily.** Showing a split creates engine tabs for every pane that has none (the
   same lazy rule as today, per pane).
   - Separating a pane keeps its engine tab ("without closing its tab").
   - Removing a node closes its engine tab through the existing `closeEngineTabsOfRemovedNodes`.
   - A Pinned or Favorite pane closed by Cmd-W shows an empty pane placeholder; clicking it reopens the page [I]
     (RT-36). Re-showing the split does not reopen it on its own.
7. **Focused pane.**
   - `ShellWindowController.currentTab` is the focused pane's engine tab.
   - `visibleNodes` is every pane of the shown split.
   - `SidebarController` draws the focused pane as `.current` and the other panes as `.contentVisible` through
     `TabRowState.Resolver.visible`. The split row already shows the strongest pane state.
   - The last focused pane per split is remembered for the window's lifetime (`[split: pane]`, not persisted) [I].
     Activating a split row focuses it; otherwise the first pane.
   - A mouse-down inside a pane, the pane shortcuts and drops change focus.
8. **What Ctrl-Shift-= puts in the new pane.** It opens the command bar in a new `.newSplitPane` mode. Enter creates
   the tab as a new pane to the right of (side by side) or below (top to bottom) the focused pane; Esc creates nothing
   [I] (RT-34). A full split shows the BH-116 toast at key press, and the bar does not open.
9. **Where a separated pane goes** (Ctrl-Shift--, Remove Tab from Split View): into the split's parent location, right
   after the split (or after the surviving tab when the split collapses). It is not archived and its engine tab stays
   (CF-18) [I] (RT-21). Focus stays on the surviving pane next to it in the split.
10. **Visibility contract (Track E decision 10) for splits.**
    - `onTabHidden` fires for every pane that leaves the screen when the card switches.
    - `windowWillClose` and termination stamp every visible pane.
    - Auto-archive exempts every visible pane (`AppSession` already reads `resolver.visible`). The split-as-a-unit
      rule in `AutoArchivePolicy` then protects the whole split.
11. **Drop zones (GS-011).** The sources conflict: the design and the issue say "page edge"; GS-011 and BH-117 say
    "content center, top or bottom center for vertical". The spec wins (design section 3: "Exact rules ... come from
    the parity spec").
    - Left third → new pane on the left, side by side.
    - Right third or the middle band → right, side by side.
    - Top quarter of the middle column → top, top to bottom.
    - Bottom quarter of the middle column → bottom, top to bottom.
    - A translucent preview shows where the new pane will go (flag `sidebarDragToSplitPreviewUIEnabled`).
    - PARITY(NEEDS-RUNTIME-CHECK RT-32).
12. **Menus.** A "Split View" submenu in the View menu [I] (RT-38) with:
    - Add Split View Pane (Ctrl-Shift-=) and Close Split Pane (Ctrl-Shift--);
    - Focus Pane 1-4 and Next / Previous Pane;
    - Expand Current Split and Separate Page from Split View (both unbound, KB-075);
    - Convert to Horizontal / Vertical Split View (BH-120) and Add Right / Left / Top / Bottom Split (BH-117).

    `validateMenuItem` disables the pane items when the current tab is not in a split.

    Amended in S5 (#55) by the RT-38 passive read in #78: Arc's View menu holds Add Split View, Close this Split
    Pane, Separate Page from Split View and Expand Current Split directly, with those titles. The other items sit in
    the "Split View" submenu [I]. See "Notes from S5".
13. **Error surface.** ShellUI cannot see `SidebarError`. `ModelSidebarSource` turns `.splitFull` into
    `ShellUI.SplitEditError.splitFull` and the other split errors into `.invalid`. New `SidebarMutation` cases are
    `.addPane` and `.editSplit`. `errorText(for:)` returns "Cannot Add New Pane" (BH-116, exact [S] string) for
    `.splitFull`.

## New runtime checks (added to the spec's RT table in S0)

| RT | Rows | What to measure in a fresh Arc (separate macOS test user) |
|---|---|---|
| RT-31 | BH-120, decision 1 | Create a side-by-side split, quit Arc, read that test account's `StorableSidebar.json` `layoutOrientation`; repeat for top-bottom |
| RT-32 | GS-011, BH-117 | Drag a sidebar tab over the content: map the drop zones (edges, center, top or bottom center), the preview shape and the side the new pane lands on |
| RT-33 | decision 4 | Minimum pane width and height; whether a divider drag resizes only the adjacent panes; what a double-click on the divider does |
| RT-34 | KB-070 | What Ctrl-Shift-= shows in the new pane (blank, command bar, duplicate); what Esc does |
| RT-35 | decision 2 | The pane shares after adding a 3rd or 4th pane (equal or proportional) |
| RT-36 | BH-123, BH-067 | Cmd-W on a pane of a Pinned split: what the pane area shows afterwards |
| RT-37 | S3, S4 | The gap between panes, the focused-pane indicator (border, dimming), the pane header controls above each pane |
| RT-38 | KB-070 to KB-075 | The menu bar location and titles of the Split View items |

Existing rows used here: RT-06 (KB-073 keys and direction), RT-21 (Ctrl-Shift-- versus Cmd-W), RT-22 (Opt-click the
close button).

## File map (end state)

```
app/ArktCore/
  Sources/SidebarModel/SidebarModel.swift            (S1: SidebarError cases, cap in move, collapse helper shared with removePane)
  Sources/SidebarModel/Sidebar+Split.swift           (S1: split operations)
  Tests/SidebarModelTests/SplitOperationsTests.swift (S1)
  Tests/SidebarModelTests/SidebarStorageFormatTests.swift (S1: round trip of a split built by the operations)
app/ArktShell/
  App/MainMenu.swift                                 (S5: View > Split View submenu)
  ShellKit/Sources/ShellUI/Sidebar/SidebarSource.swift   (S2: SplitOrientation, SplitLayoutInfo, .split(id:layout:), split writes, SplitEditError)
  ShellKit/Sources/ShellUI/Sidebar/StubSidebar.swift     (S2)
  ShellKit/Sources/ShellUI/Sidebar/SidebarController.swift (S4: visible set, preferred pane)
  ShellKit/Sources/ShellUI/Sidebar/SidebarOutlineController.swift (S6: context menus, Opt-click; S7: drag source)
  ShellKit/Sources/ShellUI/Split/SplitLayout.swift        (S3: pure frames, normalization, divider math)
  ShellKit/Sources/ShellUI/Split/SplitFocus.swift         (S3: pane N, next/previous with wraparound)
  ShellKit/Sources/ShellUI/Split/SplitDividerView.swift   (S3)
  ShellKit/Sources/ShellUI/Split/SplitContainerView.swift (S3, S4)
  ShellKit/Sources/ShellUI/Split/SplitDropZone.swift      (S7: pure)
  ShellKit/Sources/ShellUI/Split/SplitDropOverlayView.swift (S7)
  ShellKit/Sources/ShellUI/Window/ShellRootView.swift     (S3: split container next to the card)
  ShellKit/Sources/ShellUI/Window/ShellWindowController.swift (S4: show() goes through the split path; S5: validateMenuItem)
  ShellKit/Sources/ShellUI/Window/ShellWindowController+Split.swift (S4, S5, S7)
  ShellKit/Sources/ShellUI/CommandBar/CommandBarController.swift (S5: .newSplitPane mode; S6: caption)
  ShellKit/Sources/CoreBridge/BridgeMapping.swift         (S2)
  ShellKit/Sources/CoreBridge/ModelSidebarSource.swift    (S2)
  ShellKit/Tests/ShellUITests/SplitLayoutTests.swift, SplitFocusTests.swift, SplitDropZoneTests.swift
  ShellKit/Tests/CoreBridgeTests/SidebarSourceContractTests.swift (S2), ModelSidebarSourceTests.swift (S2), SidebarDiffTests.swift (S2)
  ShellKit/Tests/ShellKitGUITests/FrameTestSupport.swift   (S9: FrameScript and StableFrames moved out of SpacePagerTests)
  ShellKit/Tests/ShellKitGUITests/SplitContainerViewTests.swift (S3), SplitWindowTests.swift (S4),
    SplitShortcutTests.swift (S5), SplitSidebarTests.swift (S6), SplitDragTests.swift (S7),
    SplitArchiveTests.swift (S8), SplitPacingTests.swift (S9)
docs/spec/arc-parity-spec.md                         (S0: RT-31..RT-38)
docs/plans/2026-10-2x-split-view-results.md          (S9)
```

**Execution order:** S0, S1, S2, S3, S4, then S5, S6 and S7 (in that order; they all touch
`ShellWindowController+Split.swift` and `MainMenu`, so merge each before branching the next), then S8, then S9. S3's
pure `SplitLayout` part may start in parallel with S2 if a second build slot is free, because it only needs
`SplitOrientation`, which S3 can copy from S2's branch.

---

### Task S0: Worktree, baselines, runtime-check rows

**Files:**
- Modify: `docs/spec/arc-parity-spec.md` (add rows RT-31..RT-38 from the table above, nothing else)

**Steps**
1. Confirm the start condition and create the worktree:
   ```zsh
   cd /path/to/arkt && git fetch && git log --oneline -3 origin/main | cat
   git log origin/main --oneline | grep -c "E5b: Cmd-W"            # must print 1
   git worktree add ../arkt-wt/split -b feat/27-s0-runtime-checks origin/main
   ```
2. Record the baselines (Core, ShellKit pure, ShellKit GUI) in the task log; S9 writes them into the results file.
   ```zsh
   cd $CORE && nice -n 20 swift test -j 2 2>&1 | tail -3
   cd $KIT && nice -n 20 swift test -j 2 --skip ShellKitGUITests 2>&1 | tail -3
   cd $KIT && nice -n 20 swift test -j 2 --filter ShellKitGUITests 2>&1 | tail -3
   ```
3. Add the RT rows. Docs only, so no test.

**Commit:** `Split View: add runtime checks RT-31 to RT-38 to the parity spec`

---

### Task S1: Model operations (ArktCore)

**Parity:** BH-115, BH-116, BH-119, BH-120, BH-121, BH-122, BH-124, CF-06, CF-18.

**Files:**
- Modify: `$CORE/Sources/SidebarModel/SidebarModel.swift`
- Create: `$CORE/Sources/SidebarModel/Sidebar+Split.swift`
- Create: `$CORE/Tests/SidebarModelTests/SplitOperationsTests.swift`
- Modify: `$CORE/Tests/SidebarModelTests/SidebarStorageFormatTests.swift`

**API** (load-bearing signatures; doc comments carry the [I] and PARITY markers):

```swift
extension SidebarError {
  // added cases in the enum itself:
  // case splitFull(NodeID)        // BH-116: the split already holds maximumSplitPanes
  // case invalidSplit(NodeID)     // wrong pane count, a non-tab, duplicate ids, bad width factors
}

extension Sidebar {
  public static let maximumSplitPanes = 4

  /// New split at the place of `tabs[0]` (same location and index; BH-119), holding `tabs` in order with equal
  /// shares. 2...4 distinct tab ids. Tabs may come from anywhere, including another split (which shrinks or
  /// collapses). Throws `.invalidSplit` / `.unknownNode`; unchanged on throw.
  @discardableResult
  public mutating func createSplit(of tabs: [NodeID], orientation: Orientation = .horizontal,
                                   createdAt: Date = .now) throws -> NodeID

  /// Moves an existing tab into `split` at `index` (nil appends). Equalizes shares [I] (RT-35). Throws `.splitFull`.
  public mutating func addPane(_ tab: NodeID, to split: NodeID, at index: Int? = nil) throws

  /// Ctrl-Shift-- (BH-122, CF-18): the pane leaves the split, keeps its id, and lands right after the split in the
  /// split's parent [I] (RT-21). The others rescale proportionally; one survivor replaces the split.
  public mutating func separatePane(_ pane: NodeID) throws

  /// Separate All Tabs (BH-121, GS-033): the panes take the split's place, in order; the split is removed.
  @discardableResult public mutating func separateSplit(_ split: NodeID) throws -> [NodeID]

  /// Expand Current Split (BH-124): `pane` stays where the split was, the others follow it in order.
  public mutating func expandPane(_ pane: NodeID) throws

  /// Reorders inside the split; factors follow their panes. `index` uses `move`'s before-removal convention.
  public mutating func movePane(_ pane: NodeID, to index: Int) throws

  /// Divider commit: `factors.count == panes`, every value finite and > 0; stored normalized to sum 1.
  public mutating func setSplitWidthFactors(_ split: NodeID, _ factors: [Double]) throws

  public mutating func setSplitOrientation(_ split: NodeID, _ orientation: Orientation) throws
}
```

Implementation notes:
- Move the collapse logic out of `removePane` into a private `shrinkSplit(_ splitID:, removedIndex:, survivorIndex:)`,
  shared by `removePane` and `separatePane`. `removePane`'s behavior and its tests must not change.
- `move(_:to:at:)` into `.split(s)` throws `.splitFull(s)` when the split already holds 4 panes and the node is not
  already in it. `validate` and `insert` do not change (decision 3).
- `createSplit` is a copy-then-commit: run on `var copy = self`, assign only on success, as `insert` does.
- All operations bound recursion in the same way as the existing `depth` and `height` helpers.

**Steps**
1. Write `SplitOperationsTests.swift`. Use `#expect` and `#expect(throws:)`, with a world built the way `SidebarTests`
   builds one: a Space with tabs in Pinned and Today and a folder. Tests:
   - `createSplitTakesFirstTabsPlace`: Today `[a, b, c]` → `createSplit(of: [b, a])` → Today `[split, c]`, panes `[b,
     a]`, factors `[0.5, 0.5]`, orientation `.horizontal`.
   - `createSplitInPinnedStaysPinned` (BH-119).
   - `createSplitPullsPaneOutOfAnotherSplitAndCollapsesIt`.
   - `createSplitRejectsOneOrFiveTabsDuplicatesAndNonTabs` throws `.invalidSplit`, and the sidebar is unchanged (`==`
     the copy taken before).
   - `addPaneEqualizesAndCapsAtFour`: 2 → 3 gives `[1/3, 1/3, 1/3]`; the 5th throws `.splitFull(split)`; unchanged on
     throw.
   - `moveIntoFullSplitThrowsSplitFull`; `insertOfFivePaneSnapshotStillLoads` (decision 3).
   - `separatePaneLandsAfterSplitAndRescales`: 3 panes `[0.5, 0.25, 0.25]`, separating the first → parent `[split,
     p0]`, factors `[0.5, 0.5]`.
   - `separatePaneOfTwoCollapsesToSurvivorThenSeparated`: parent `[p1, p0]`, the split node is gone, p1 keeps its id.
   - `separateSplitPutsPanesInPlaceInOrder`; `expandPaneKeepsFocusedFirst`.
   - `movePaneReordersFactorsWithPanes`.
   - `setSplitWidthFactorsNormalizesAndRejectsBadInput`: `[2, 2]` → `[0.5, 0.5]`; `[1]` for two panes, `[0, 1]` and
     `[.nan, 1]` all throw `.invalidSplit`.
   - `setSplitOrientationChangesOnlyOrientation`.
   - `removePaneUnchanged`: re-assert the E5b cases still hold after the refactor.
2. In `SidebarStorageFormatTests`, add `splitBuiltByOperationsRoundTrips` (`createSplit`, `addPane`,
   `setSplitWidthFactors`, encode, decode, `==`).
3. Run Core; the new tests fail to compile.
4. Implement. Run Core and expect baseline + 16 (approximately; record the exact number).
5. Run Core again to confirm the Archive and ArcImport tests still pass. `Archiver` uses `removePane`.

**Verification:** `cd $CORE && nice -n 20 swift test -j 2 2>&1 | tail -5`

**Commit:** `Split operations in the sidebar model: create, add pane (max 4), separate, expand, reorder, widths,
orientation`

---

### Task S2: Shell vocabulary and source writes (ShellUI, CoreBridge)

**Parity:** BH-115, BH-116 (error mapping), BH-120.

**Files:**
- Modify: `$KIT/Sources/ShellUI/Sidebar/SidebarSource.swift`, `$KIT/Sources/ShellUI/Sidebar/StubSidebar.swift`
- Modify: `$KIT/Sources/CoreBridge/BridgeMapping.swift`, `$KIT/Sources/CoreBridge/ModelSidebarSource.swift`
- Modify: `$KIT/Sources/ShellUI/Window/ShellWindowController.swift` (`SidebarMutation` cases and `errorText` only)
- Modify (pattern updates): `SidebarOutlineController.swift` and `CommandBarResults.swift`, wherever they match
  `.split`
- Tests: `$KIT/Tests/CoreBridgeTests/SidebarSourceContractTests.swift`, `ModelSidebarSourceTests.swift`,
  `SidebarDiffTests.swift`

**API (ShellUI):**

```swift
public enum SplitOrientation: String, Hashable, Sendable { case horizontal, vertical }   // mirrors SidebarModel.Orientation
public struct SplitLayoutInfo: Equatable, Sendable {
  public var orientation: SplitOrientation
  public var widthFactors: [Double]
}
// SidebarNodeInfo: case split(id: NodeID, layout: SplitLayoutInfo)

public enum SplitEditError: Error, Equatable, Sendable { case splitFull, invalid }
public enum SplitPaneSource: Equatable, Sendable { case existing(NodeID), new(url: URL, title: String) }

// SidebarSource additions:
/// `target` is a plain tab (a new split is created at its place, holding target and the new pane, with
/// `orientation`) or a pane or split (the pane is added to that split at `index`). Returns the split and the pane.
@discardableResult
func addToSplit(_ pane: SplitPaneSource, target: NodeID, at index: Int, orientation: SplitOrientation) throws
  -> (split: NodeID, pane: NodeID)
func separatePane(_ pane: NodeID) throws
@discardableResult func separateSplit(_ split: NodeID) throws -> [NodeID]
func expandPane(_ pane: NodeID) throws
func movePane(_ pane: NodeID, to index: Int) throws
func setSplitWidthFactors(_ split: NodeID, _ factors: [Double]) throws
func setSplitOrientation(_ split: NodeID, _ orientation: SplitOrientation) throws
@discardableResult func duplicateSplit(_ split: NodeID) throws -> NodeID   // BH-126 "Duplicate split"
```

Notes:
- `ModelSidebarSource.addToSplit(.new(...))` adds the tab and the pane inside ONE `mutate` closure: `addTab` into the
  target's location, then `createSplit` or `addPane`. The result is one diff and one `onDidChange`, and a `.splitFull`
  throw leaves no orphan tab.
- `lastActiveAt` is set to `now()` as in `addTab`.
- Error mapping: `SidebarError.splitFull` → `SplitEditError.splitFull`; `.invalidSplit` → `.invalid`; others are
  rethrown as they are.
- `duplicateSplit`: the snapshot with fresh ids, inserted after the original.
- `StubSidebar` implements the same semantics with simple array operations; the contract tests hold both to it.
- With `layout` in `SidebarNodeInfo`, `SidebarDiff` emits `.node(split)` when factors or orientation change. That is
  expected and asserted.
- `SidebarMutation` gains `.addPane` and `.editSplit`. `errorText(for:error:)` returns "Cannot Add New Pane" for
  `SplitEditError.splitFull` and "Couldn't change the Split View." for anything else [I].

**Steps**
1. Contract tests, parameterized over `SourceKind.allCases` like the existing ones:
   - `addToSplitNewCreatesSplitAtTargetsPlace` checks children, the layout `[0.5, 0.5]` and the changes:
     `.structure(.today)` plus `.structure(.split)`, in diff order for the model source. Assert only the set for Stub.
   - `addToSplitFifthThrowsSplitFullAndChangesNothing` (no emission, no orphan tab).
   - `separatePaneKeepsTabAfterSplit`; `separateSplitRestoresOrder`; `expandPaneKeepsFocusedFirst`.
   - `setSplitWidthFactorsEmitsNodeChangeOnly` (`[.node(split)]`).
   - `setSplitOrientationEmitsNodeChange`.
2. `ModelSidebarSourceTests`:
   - the `node(split)` expectation becomes `.split(id:layout:)`;
   - `addToSplitIsOneMutation` (`onDidChange` called once);
   - `errorsMapToSplitEditError`.
3. `SidebarDiffTests`: `widthChangeEmitsNodeOfSplit`.
4. Run the ShellKit pure tests; they fail to compile.
5. Implement, then update the `.split` pattern matches (5 sites in ShellUI and CoreBridge).
6. Run the ShellKit pure and isolation tests, then the GUI tests (`SidebarViewTests` and `CloseTabTests` still pass).

**Verification:** the ShellKit pure, isolation and GUI commands.

**Commit:** `Split layout in the shell's sidebar vocabulary and split writes on SidebarSource`

---

### Task S3: Split container, layout math and divider drag (Core Animation frames)

**Parity:** design section 3 (divider drives layer frames), BH-128 (focus math), decision 4.

**Files:**
- Create: `$KIT/Sources/ShellUI/Split/SplitLayout.swift`, `SplitFocus.swift`, `SplitDividerView.swift`,
  `SplitContainerView.swift`
- Modify: `$KIT/Sources/ShellUI/Window/ShellRootView.swift` (adds `split: SplitContainerView`, laid out at
  `cardFrame`, hidden by default)
- Tests: `$KIT/Tests/ShellUITests/SplitLayoutTests.swift`, `SplitFocusTests.swift`;
  `$KIT/Tests/ShellKitGUITests/SplitContainerViewTests.swift`

**API:**

```swift
public enum SplitAxis: Sendable { case sideBySide, stacked }
public struct SplitFrames: Equatable, Sendable { public var panes: [CGRect]; public var dividers: [CGRect] }

public enum SplitLayout {
  public static let minimumPaneLength: CGFloat = 240        // [I] PARITY(NEEDS-RUNTIME-CHECK RT-33)
  /// Decision 1: the only place a stored orientation becomes an axis.
  public static func axis(for orientation: SplitOrientation) -> SplitAxis
  /// Decision 2: equal shares on count mismatch; non-finite or <= 0 entries replaced; renormalized to 1.
  public static func normalized(_ factors: [Double], count: Int) -> [Double]
  /// Pixel-aligned at `scale`; the gap between panes is the divider's hit rect.
  public static func frames(in bounds: CGRect, axis: SplitAxis, factors: [Double], gap: CGFloat, scale: CGFloat) -> SplitFrames
  /// Divider `index` dragged to main-axis `position`: only panes index and index+1 change, each >= minimum;
  /// equal shares when bounds cannot fit count * minimum.
  public static func factors(dragging index: Int, to position: CGFloat, in bounds: CGRect, axis: SplitAxis,
                             factors: [Double], gap: CGFloat, minimum: CGFloat) -> [Double]
}

public enum SplitFocus {
  /// Ctrl-Shift-N (KB-072): nil when N > count.
  public static func pane(number: Int, count: Int) -> Int?
  /// KB-073 / BH-128: wraps around.
  public static func next(from index: Int, count: Int) -> Int
  public static func previous(from index: Int, count: Int) -> Int
}
```

`SplitContainerView` (an NSView, layer-backed, not flipped like `ContentCardView`):
- Holds up to 4 pane cards. Each is a `ContentCardView`, so each pane has its own rounded clip, hairline, shadow and
  Toolbar (this sets up BH-125). Between them sit N-1 `SplitDividerView`s.
- `func show(panes: [NSView?], axis: SplitAxis, factors: [Double])`. `nil` is the closed-pane placeholder from
  decision 6. Pane cards are reused, never rebuilt.
- `layout()` sets every pane and divider frame inside `CATransaction.setDisableActions(true)`.
- `focusedIndex` draws the focus indicator. Placeholder: the focused card's border uses `ShellTokens.cardBorder` at
  full strength, the others at 50% [I] (RT-37).
- `onCommitFactors: (([Double]) -> Void)?`
- `onFocusRequest: ((Int) -> Void)?`
- `liveFactors` (read-only, for tests and the pacer).
- `let pacer = FramePacer()` with `lastPacing`, the same as `SpacePagerView`.

`SplitDividerView` copies `SidebarResizeHandle`'s pattern: a `columnResize` or `rowResize` cursor,
mouse-down/dragged/up, double-click to equalize. Its programmatic API drives tests and the perf gate the way
`SpacePagerView.beginTracking/track/endTracking` does:

```swift
public func beginDrag()                       // starts the FramePacer session "split-divider"
public func drag(to position: CGFloat)        // main-axis position in the container; sets frames immediately
public func endDrag()                         // ends the pacer, fires onCommitFactors once
```

`mouseDragged` calls `drag(to:)` directly. AppKit coalesces drag events, so it is at most one frame update per event
and no extra timers.

**Steps**
1. `SplitLayoutTests` (pure):
   - `axisForOrientation` (decision 1, one assertion per case, the RT-31 anchor);
   - `normalizedPadsTruncatesAndRenormalizes`;
   - `framesTwoPaneSideBySideSplitsWidthMinusGap`;
   - `framesStackedFourPanes`;
   - `framesArePixelAligned` (scale 2);
   - `draggingChangesOnlyAdjacentPanes`;
   - `draggingClampsToMinimum`;
   - `tooSmallBoundsGiveEqualShares`;
   - `syntheticArcFixtureFactorsLayOut` (`vertical`, `[0.5, 0.5]`).
2. `SplitFocusTests`: pane number 1 to 4 against count 2 to 4, and wraparound both ways.
3. `SplitContainerViewTests` (GUI, plain colored NSViews as panes):
   - `showTwoPanesPlacesContentInCards`;
   - `dragMovesFramesWithoutCommitUntilEnd`: `beginDrag`, `drag(to:)`, frames changed, `onCommitFactors` not called;
     `endDrag` → called once with the expected factors;
   - `doubleClickEqualizes`;
   - `windowResizeKeepsFactors`;
   - `noImplicitAnimationsOnDrag` (the layers have no animation keys after `drag(to:)`);
   - `paneCardsAreReusedAcrossShowCalls`.
4. Run, fail, implement, run. Pure: baseline + ~12. GUI: baseline + 6.

**Verification:** the ShellKit pure, GUI and isolation commands.

**Commit:** `Split container: pane cards, layout math and a divider that sets frames directly`

---

### Task S4: The window shows splits; focused pane; URL bar and Toolbar follow it

**Parity:** BH-125, KB-074, BH-101 (split clause), BH-123 (kept), decision 6, decision 7, decision 10.

**Files:**
- Create: `$KIT/Sources/ShellUI/Window/ShellWindowController+Split.swift`
- Modify: `ShellWindowController.swift`
  - `show(node:)` goes through `showSplit` when the node's parent is `.split`;
  - `visibleNodes` is the shown panes;
  - `handle(_:)` covers `.tabClosed` of a pane;
  - `wireAddressBars` also wires each pane card's Toolbar;
  - `windowWillClose` stamps all panes.
- Modify: `SidebarController.swift`
  - a `visible: Set<NodeID>` setter used by `resolver`;
  - `preferredPane: ((NodeID) -> NodeID?)?`, asked by `activate(node:)` for a split before `firstTab`.
- Modify: `ContentCardView.swift` only if the toast view has to move between the single card and the split container
  (`toastView` already re-parents in its `didSet`).
- Test: `$KIT/Tests/ShellKitGUITests/SplitWindowTests.swift`. The harness is the same shape as `CloseTabTests`:
  `ModelSidebarSource` plus `InMemoryEngine`.

**Behavior**
- **Showing a split.** `showSplit(split, focus: pane)`:
  - make sure every pane has an engine tab (lazy `createTab` plus `replay`), except panes closed per decision 6;
  - `rootView.showsSplit = true`, which hides the single card and shows the container;
  - `split.show(panes:axis:factors:)` with factors from `sidebar.node(split)` and the `layout`;
  - `currentTab` = the focused pane's tab;
  - `sidebarController.visible = Set(panes)`;
  - `onTabHidden` for every previously visible node that is not in the new set;
  - remember `activePane[split] = pane`;
  - `window.makeFirstResponder(engine.contentView(for: tab))`;
  - `refreshAddress()`.
- **Showing a plain tab** undoes all of that (`showsSplit = false`) and reports the panes that are now hidden.
- **Focus by click.** `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` is installed by the controller and
  removed in `windowWillClose`. If the point lies in pane card i of the shown split and i is not focused, it calls
  `sidebarController.activate(node: panes[i])` and returns the event unchanged, so the page still gets the click. This
  is engine-agnostic: no engine view subclassing, no `hitTest` override.
- **Keeping the shown split in sync.** On `.structure(.split(s))` or `.node(s)` for the shown split, or
  `.structure(parent)` when the shown split vanished, re-show the current focus. If the focused pane is gone, use the
  successor. This is deferred one main-queue turn, as `activateRestoredTabLater` does, because showing may call
  `sidebar.updateTab` through `replay`, and a source must not be mutated during delivery.
- **Address and Toolbar** (BH-125, KB-074):
  - the sidebar URL bar shows the focused pane's URL;
  - with the Toolbar on, each pane card shows its own Toolbar and URL (the pane's `ContentToolbarView.urlBar.url` from
    its own snapshot);
  - Back, Forward and Reload on a pane card act on that pane's tab and focus it;
  - `.urlChanged` refreshes the pane's own toolbar and, when it is the focused tab, the sidebar URL bar;
  - `openLocation` (Cmd-L) already prefills from `currentTab`, which is now the focused pane, and `open(_:inNewTab:
    false)` navigates it.
- **Cmd-W** (`closeTab`) keeps the E5b behavior. After a Today pane is archived and the split still has 2 or more
  panes, the successor pane in the same split gets focus. The existing `successor(of:)` already looks in the split
  first.
- **Engine tab closed in a Pinned or Favorite split** (decision 6). `.tabClosed` of a visible pane clears only that
  pane (placeholder). It clears the card only when it is the last pane with a page. A click on the placeholder
  recreates the tab.

**Steps (tests in `SplitWindowTests`)**
1. `activatingPaneShowsAllPanesAndCreatesOneEngineTabEach` (InMemoryEngine `tabIDs.count == 2`; the container shows 2
   cards; `visibleNodes == Set(panes)`).
2. `splitRowStatesFocusedCurrentOthersContentVisible` (`controller.rowState`).
3. `activatingSplitRowRestoresLastFocusedPane`.
4. `clickInSecondPaneFocusesIt`: post a synthetic mouse-down at the card's center through `window.sendEvent`.
   Afterwards `currentTab` is pane 2's tab and `firstResponder` is its content view.
5. `switchingToPlainTabReportsEveryHiddenPane` (`hidden == panes`).
6. `cmdLNavigatesFocusedPane`: commit through the command bar's `onOpen`, then `InMemoryEngine` shows the navigation
   on pane 2 only.
7. `toolbarOnShowsPerPaneURL` and `toolbarBackActsOnItsPane`.
8. `widthCommitWritesModelOnce` (the divider's `endDrag` → the source's `onDidChange` once, and the factors stored).
9. `sourceSideOrientationChangeRelayoutsShownSplit`.
10. `separatedPaneKeepsEngineTab` (`separatePane` → `tabIDs` unchanged; the split collapses and the remaining pane
    shows as a plain tab).
11. `pinnedPaneCloseShowsPlaceholderAndClickReopens`.
12. Re-run `CloseTabTests` unchanged; all must pass.

Implement and run the GUI tests (baseline + ~13), the pure tests and the isolation tests. Then build the app and smoke
it by hand with FakeEngine: open the Work Space split and check that both pages render and that the divider drags.

**Commit:** `Show splits in the window: one engine tab per pane, focused pane drives URL bar, Toolbar and Cmd-L`

**Notes from S4 (#54)** (S5 to S8 build on these):
- **Loaded state (#156 review).** Every engine tab the window creates goes through
  `ShellWindowController.openEngineTab(for:)`, which also calls `SidebarController.markLoaded(node:)`; every
  `.tabClosed` still calls `deactivate(node:)`. So `loadedNodes` stays equal to the window's engine tabs while pane
  pages are created outside `activate`. New engine-tab creation paths (popups, background opens) must use the same
  helper.
- **Closed panes.** `SplitWindowState.closedPanes` holds panes whose page closed while the node stayed (Pinned,
  Favorites). They show the placeholder until clicked or activated; activating a pane always opens it. When no pane of
  the split has a page, the set is cleared for that split and the content area empties, so the split row opens every
  pane again.
- **Focus after a source change.** The deferred re-show keeps focus on the focused node wherever it now is (a
  separated or expanded pane stays focused as a plain tab). Decision 9's "focus stays on the surviving pane" is S5's
  job: the shortcut activates the survivor after `separatePane`.
- **Toasts.** While a split is shown, `ShellRootView.showsSplit` moves the toast view from the hidden single card to
  the split container, centered on the whole content area.
- **Click focus in tests.** Local event monitors run in `NSApplication.sendEvent`, not `NSWindow.sendEvent`; GUI
  tests post the synthetic mouse-down through `NSApp.sendEvent`.

---

### Task S5: Shortcuts and menu items

**Parity:** KB-070, KB-071, KB-072, KB-073 (RT-06), KB-075, BH-116, BH-117 (Add Right/Left/Top/Bottom Split), BH-120,
BH-122, BH-124, BH-128.

**Files:**
- Modify: `$APP/App/MainMenu.swift` (View > Split View submenu, decision 12)
- Modify: `ShellWindowController+Split.swift` (`@objc` actions), `ShellWindowController.swift` (`validateMenuItem`)
- Modify: `$KIT/Sources/ShellUI/CommandBar/CommandBarController.swift`: `Mode` gains `.newSplitPane`; `onOpen` becomes
  `onOpen: ((URL, OpenTarget) -> Void)?` with `enum OpenTarget { case currentTab, newTab, newSplitPane }`, and every
  caller is updated.
- Test: `$KIT/Tests/ShellKitGUITests/SplitShortcutTests.swift`

**Actions:**
- `addSplitPane(_:)` (Ctrl-Shift-=). If the current tab is in a split of 4 → BH-116 toast, no bar. Otherwise
  `commandBar.toggle(.newSplitPane)`. On Enter: `addToSplit(.new(url, host), target: current, at: focusedIndex + 1,
  orientation: .horizontal)`, then activate the new pane. PARITY(NEEDS-RUNTIME-CHECK RT-34).
- `closeSplitPane(_:)` (Ctrl-Shift--) → `separatePane(focused)`; focus moves to the neighbor pane (decision 9). It
  never calls `onArchive` (CF-18).
- `focusSplitPane(_:)`: menu items tagged 0 to 3, Ctrl-Shift-1...4 → `SplitFocus.pane(number:count:)`.
- `nextSplitPane(_:)` / `previousSplitPane(_:)`: Ctrl-Shift-] is next and Ctrl-Shift-[ is previous (KB-073 as listed,
  CF-16 unresolved). PARITY(NEEDS-RUNTIME-CHECK RT-06).
- `expandCurrentSplit(_:)` and `separatePageFromSplit(_:)`: unbound (KB-075). They call `expandPane` and
  `separatePane`.
- `convertSplitOrientation(_:)`: titled "Convert to Vertical Split View" or "Convert to Horizontal Split View" by
  `validateMenuItem` (BH-120).
- `addSplitRight/Left/Top/Bottom(_:)`: unbound (BH-117), the same flow as `addSplitPane` with an explicit side and
  orientation.

**Key equivalent trap.** For an item with `.shift`, AppKit matches the shifted character on some layouts: "=" versus
"+", "-" versus "_", "1" versus "!", "]" versus "}".
- Write the tests first. They build the key events with `NSEvent.keyEvent(..., modifierFlags: [.control, .shift],
  characters: "+", charactersIgnoringModifiers: "=", keyCode: kVK_ANSI_Equal)` and assert
  `NSApp.mainMenu!.performKeyEquivalent(event)` reaches the action. Choose the `keyEquivalent` string that passes: the
  unshifted base with `.shift` on current macOS, but verify it.
- If a key cannot be matched reliably on the US layout, bind it with a local key-down monitor keyed on `keyCode` (the
  Carbon `kVK_ANSI_*` constants) and keep the menu item unbound but titled. Record the choice in the results file.
- Non-US layouts are a recorded risk, not a gate.

**Steps (tests)**
1. `ctrlShiftEqualsOpensBarInSplitPaneModeAndEnterAddsPane`.
2. `ctrlShiftEqualsOnFullSplitShowsCannotAddNewPaneToast` (`toasts` text equals "Cannot Add New Pane"; no bar).
3. `ctrlShiftMinusSeparatesFocusedPaneWithoutArchiving` (`archived` stays empty; the tab sits after the split).
4. `ctrlShiftNumberFocusesPaneN` and `numberBeyondCountDoesNothing`.
5. `nextPreviousWrapAround`.
6. `expandCurrentSplitKeepsFocusedShown`.
7. `convertFlipsOrientationAndRetitles`.
8. `paneItemsDisabledOutsideSplit` (`validateMenuItem`).
9. `menuKeyEquivalentsReachActions`. `MainMenu` lives in the App target, so assert on a menu built by a `ShellUI`-side
   `SplitMenu.items()` that `MainMenu` calls. Put the item list in ShellUI so it is testable.

Run the GUI, pure and isolation tests and the App build. Manual check in the app: every shortcut in the KB rows, with
a US keyboard layout.

**Commit:** `Split View shortcuts and View menu items: add, close, focus, next and previous pane, expand, convert`

**Notes from S5 (#55)** (S6 to S9 build on these):
- **Menu shape.** `ShellUI.SplitMenu.items()` builds the items and `MainMenu` appends them to the View menu after the
  Toolbar item. Directly in View, with Arc's titles (RT-38, passive read in #78, no split showing): Add Split View
  (Ctrl-Shift-=), Close this Split Pane (Ctrl-Shift--), Separate Page from Split View, Expand Current Split. In a
  "Split View" submenu [I]: Convert to Vertical / Horizontal Split View, Add Right / Left / Top / Bottom Split, Next /
  Previous Split View Pane (Ctrl-Shift-] / [), Switch to Split View 1 to 4 (Ctrl-Shift-1 to 4). The titles while a
  split is showing are still RT-38.
- **Key equivalents** (for the S9 results file). Each item uses the unshifted US character with `[.control, .shift]`
  ("=", "-", "]", "[", "1" to "4"). A real Ctrl-Shift-= arrives with charactersIgnoringModifiers "+"; AppKit still
  matches the "=" item when the event carries the keyboard layout, and does not match a "+" item with Ctrl-Shift.
  Checked with Quartz-built key events (`NSEvent(cgEvent:)`, translated by the current layout) in
  `SplitShortcutTests` and `MainMenuKeyEquivalentTests`; the latter also checks that every split shortcut matches only
  its own item and that Ctrl-1 to Ctrl-4 still reach only the Space items. No keyCode monitor fallback was needed.
  Non-US layouts are a recorded risk: the tests skip when the layout's keys differ from US.
- **Command bar.** `CommandBarController.onOpen` is `(URL, OpenTarget)`, `OpenTarget` = `.currentTab`, `.newTab`,
  `.newSplitPane`. In `.newSplitPane` mode Cmd-Enter / Opt-Enter still open a plain new tab, and a "Switch to Tab"
  result still switches [I]. The side the bar was opened for is `SplitWindowState.pendingSide`, read at Enter.
- **Validation.** `ShellWindowController.validateSplitMenuItem` (in `+Split.swift`) answers for the split items;
  `validateMenuItem` delegates to it first. The actions read the split from the source, not from `splitState`, so they
  work between a source change and its deferred re-show.
- **Focus.** Close this Split Pane focuses the pane after the separated one, else the one before (decision 9).
  Separate Page from Split View keeps focus on the separated page [I]; Expand Current Split keeps it on the expanded
  pane.

---

### Task S6: Sidebar split row interactions

**Parity:** BH-120, BH-121, BH-126 (Duplicate only), GS-032, GS-033, BH-104 (caption).

**Files:**
- Modify: `SidebarOutlineController.swift`
  - `outlineView.menu` plus `NSMenuDelegate.menuNeedsUpdate`, built from `clickedRow`;
  - an Opt-click branch in `rowClicked`;
  - new callbacks `onSeparateSplit`, `onRemovePane`, `onConvertSplit`, `onDuplicateSplit`, `onDuplicateIntoSplit`.
- Modify: `SidebarController.swift`, which forwards those callbacks.
- Modify: `ShellWindowController+Split.swift`, which wires them to the source.
- Modify: `CommandBarResults.swift` (an `OpenTab.isSplitPane` flag) and `CommandBarView`, wherever the caption is
  drawn: "Switch to Split View" versus "Switch to Tab".
- Tests: `$KIT/Tests/ShellKitGUITests/SplitSidebarTests.swift`,
  `$KIT/Tests/ShellUITests/CommandBarOpenTabsTests.swift`

**Behavior:**
- Split row menu: "Separate All Tabs", "Convert to Vertical Split View" or "Convert to Horizontal Split View",
  "Duplicate Split View".
- Pane row menu: "Remove Tab from Split View" ([S] string) → `separatePane`.
- Opt-click on a split row → `separateSplit` (GS-033). Focus stays on the previously focused pane, now a plain tab.
- Opt-click on the current plain tab → `addToSplit(.new(url: same, title: same), target: current, at: 1, orientation:
  .horizontal)` (GS-032), then the new pane gets focus. Flag noted: `dragToCombineTabsIntoSplitEnabled` /
  `newSplitSeparationMechanismsEnabled` [S]; always on here [I].
- Pane X button: the row close button from #8 (`RowCloseAction`) calls `separatePane` on a pane row ("Remove Tab from
  Split View", BH-121).

**Steps (tests)**
1. `splitRowMenuHasSeparateConvertDuplicate`, and `paneRowMenuHasRemoveFromSplit`. Build the menu by calling
   `menuNeedsUpdate` with a stubbed `clickedRow`, through a `@testable` hook `menu(forRow:)`.
2. `separateAllTabsRestoresPlainRowsInPlace` (outline rows, with no `reloadData`: assert `rowConfigureCount` grows
   only for the affected rows).
3. `optClickSplitRowSeparates`, using `NSEvent` with `.option` through a test hook `handleClick(row:modifiers:)`.
4. `optClickCurrentTabDuplicatesIntoSplit`.
5. `convertFromMenuFlipsShownLayout`.
6. `duplicateSplitInsertsCopyAfter`.
7. `openTabsMarksSplitPanes` (pure).

**Commit:** `Sidebar split rows: separate, remove pane, convert, duplicate, Opt-click shortcuts, command bar caption`

**Notes from S6 (#56)** (S7 to S9 build on these):
- **Pane row X.** Decision (maintainer, 2026-10-23, #56): the X on a pane row removes the pane from its split as
  its own tab, like Arc (BH-121), in every section. `RowCloseAction.removeFromSplit` gives it the tooltip and
  VoiceOver name "Remove Tab from Split View" [S], and `SidebarOutlineController.closeClicked` sends it to
  `onRemovePane`. Cmd-W on a pane keeps user decision 4 (a Today pane is archived alone, a Pinned or Favorite pane
  closes its page). The pane row's context menu also has Remove Tab from Split View.
- **Callbacks.** `SidebarOutlineController` has `onSeparateSplit`, `onRemovePane`, `onConvertSplit`,
  `onDuplicateSplit` and `onDuplicateIntoSplit`; `SidebarController` forwards them and
  `ShellWindowController.wireSplitRows()` maps them to the source. The pane X, Remove Tab from Split View and
  Ctrl-Shift-- share `removeFromSplit(_:)`: focus moves to the neighbor only when the removed pane was focused
  (decision 9).
- **Opt-click.** `SidebarOutlineView.mouseDown` records the click's modifier flags; `handleClick(row:modifiers:)`
  decides. Opt-click on a split row separates it without activating it; Opt-click on the current plain tab
  duplicates it into a split; Opt-click on any other tab or on a pane activates it like a plain click [I].
- **Menus.** `outlineView.menu` is filled in `menuNeedsUpdate` from `menu(forRow:)`: a split row gets Separate All
  Tabs, Convert to Vertical / Horizontal Split View and Duplicate Split View ([I] title); a pane row gets Remove Tab
  from Split View; other rows get no menu. Mute, Share and Archive Below stay deferred (BH-126).
- **Closed panes off screen.** A page that closes in a split that is not shown (the X on a Pinned split row, or the
  page closing itself) now records the pane in `SplitWindowState.closedPanes` (`hiddenPaneDidClose`), with the same "no
  pane has a page, forget the set" rule. `resyncSplit` drops closed panes that are no longer panes.
- **Command bar.** `OpenTab.isSplitPane` picks the caption "Switch to Split View" (BH-104); a split still contributes
  only its first pane. `CommandBarController.commit` takes an explicit `OpenTarget?` (nil: the mode decides) instead
  of mapping a `Bool` to `.currentTab`.
- **Waiting in GUI tests (#190).** `waitUntil(_:timeout:_:)` (`ShellKitGUITests/StateWait.swift`) turns the run loop
  until the asserted state holds and names that state on timeout. `SplitWindowTests` and `SplitSidebarTests` use it;
  `ModelSidebarSource` emits synchronously, so `resyncPending` is already true when a source write returns.

---

### Task S7: Drag a sidebar tab onto the page to split

**Parity:** GS-011, BH-117 (drag), BH-116 (drop on a full split), decision 11 (RT-32).

**Files:**
- Create: `$KIT/Sources/ShellUI/Split/SplitDropZone.swift` (pure), `SplitDropOverlayView.swift`
- Modify: `SidebarOutlineController.swift`
  - drag source: `outlineView(_:pasteboardWriterForItem:)` for tab rows only (not folders, splits or the divider),
    writing a `NSPasteboardItem` with the private type `dev.arkt.sidebar-node` and the node UUID string;
  - `draggingSession(_:willBeginAt:forItems:)` and `...endedAt...` forward `onNodeDragBegan` / `onNodeDragEnded`;
  - `setDraggingSourceOperationMask(.move, forLocal: true)`.
- Modify: `ShellWindowController+Split.swift`, which shows and hides the overlay and performs the drop.
- Tests: `$KIT/Tests/ShellUITests/SplitDropZoneTests.swift`, `$KIT/Tests/ShellKitGUITests/SplitDragTests.swift`

**Design:**
- **Why the overlay is temporary.** WKWebView (and later Chromium's view) registers for drags itself and is the
  deepest view under the pointer. A permanent drop target above it would also block clicks.
- **Overlay life.** `SplitDropOverlayView` is added above the card or container only between drag began and drag
  ended. It registers only `dev.arkt.sidebar-node`, and `hitTest` returns nil, so clicks pass through.
- **Preview.** `draggingUpdated` computes `SplitDropZone.zone(for:in:)` (decision 11) and moves a single preview
  `CALayer` (translucent, rounded) to the would-be pane frame, using `SplitLayout.frames` with the extra pane. Frames
  are set directly with actions disabled.
- **Drop.**
  - Dropped tab == current tab, or not a tab → reject.
  - Current is a plain tab → `addToSplit(.existing(dragged), target: current, at: side index, orientation: zone
    axis)`.
  - Current is a split → `addPane` at the zone index. A full split shows the BH-116 toast and is rejected.
  - Dragged tab is a pane of the shown split → `movePane` (reorder).
  - Focus goes to the dropped pane.
- **Placement.** The split lands at the current tab's place, as `createSplit` does. The dragged tab leaves its
  section, which is fine for Today and Pinned, and Favorites by BH-115. A Favorite dragged in is moved, not copied [I]
  (RT-32).

**Steps**
1. `SplitDropZoneTests`: one test per zone boundary, plus the stacked zones and a degenerate rect.
2. `SplitDragTests` (GUI). The drag session is not synthesized; the overlay's `performDragOperation` path is driven
   through a `@testable` `drop(node:at:)` and `preview(at:)`, and the outline's pasteboard writer is asserted
   directly:
   - `pasteboardWriterOnlyForTabs`;
   - `overlayAbsentOutsideDragAndPassesClicks`;
   - `dropRightCreatesSideBySideSplitAtCurrentsPlace`;
   - `dropTopCreatesStackedSplit`;
   - `dropOnFullSplitShowsToast`;
   - `dropPaneOfShownSplitReorders`;
   - `previewFrameMatchesFutureLayout`.
3. Manual check in the app (FakeEngine): drag a Today tab over a loaded page, see the preview, drop it, and get two
   panes.

**Commit:** `Drag a sidebar tab onto the page to split it, with a drop preview`

**Notes from S7 (#57)** (S8 and S9 build on these):
- **Drag source.** `SidebarOutlineController` writes a `NSPasteboardItem` with `.sidebarNode`
  (`dev.arkt.sidebar-node`, the node's UUID string) for tab rows only: plain tabs, tabs in folders and panes. The
  mask is `.move` inside the app and none outside it. `draggingSessionWillBegin(items:)` and `draggingSessionEnded()`
  forward `onNodeDragBegan` / `onNodeDragEnded` through `SidebarController` to `wireSplitDrag()`. `FavoritesGridView`
  (#214) is a drag source for tab tiles too (not folders), with the same `.sidebarNode` item, `.move` local mask and
  session hooks, so a Favorite dragged onto the page is moved into the split.
- **Overlay.** `SplitDropOverlayView` is made on the first drag, kept in `SplitWindowState.dropOverlay`, and added
  above the split container (at the content area's frame) only between drag start and end. It registers only
  `.sidebarNode` and its `hitTest` returns nil. The preview layer moves only when the zone under the pointer (or the
  bounds) changes, inside `CATransaction.setDisableActions(true)`; the pasteboard is read once, at the drop.
- **Drop rules** (`ShellWindowController.splitDrop(of:in:)`, `SplitDrop`).
  - Current plain tab: a new split at its place, the dropped tab first for left and top, second for right and
    bottom, with the zone's axis. The current tab dropped on itself is refused.
  - Shown split (the current tab is a pane): the dropped tab is inserted first (left, top) or last (right, bottom);
    the split keeps its orientation, so a top or bottom drop on a side-by-side split adds a pane side by side [I]
    (RT-32). A full split takes the drop, shows no preview, and the drop shows "Cannot Add New Pane" (BH-116).
  - A pane of the shown split, focused or not, moves to the front or the back (`movePane`, factors follow). A pane
    dropped where it already is is refused. The plan's "dropped tab == current tab → reject" applies to a plain
    current tab only.
  - The dropped tab gets focus. Errors go to `onError` (`.addPane`, or `.editSplit` for a reorder).
- **Preview.** `SplitDropTarget.pane(frame)` comes from `SplitLayout.frames` with the container's gap and backing
  scale, with equal shares for a new pane (RT-35) and the moved factor for a reorder, so it equals the pane card's
  frame after the drop (`testPreviewFrameMatchesFutureLayout`).

---

### Task S8: Archive, restore, auto-archive and persistence with splits

**Start condition:** #4 (E5c Archive window), already merged in #49.

**Parity:** BH-123 (user decision 4), BH-086 (split restore), BH-080 and AutoArchivePolicy split rule [I], decision
10, CF-18.

**Files:**
- Modify only where the tests show a gap. Expected touch points: `App/AppSession.swift`, which must stamp every
  visible pane at termination through `window.visibleNodes` (already a set), and `CoreBridge/ArchiveListModel.swift`
  if a split row's detail text needs the pane count.
- Tests: `$KIT/Tests/ShellKitGUITests/SplitArchiveTests.swift`;
  `$KIT/Tests/CoreBridgeTests/AutoArchiveTimerTests.swift`; `$CORE/Tests/ArchiveTests/ArchiverTests.swift`

**Steps (tests first; most should already pass and lock behavior in)**
1. `cmdWOnPaneOfThreeArchivesOnlyItAndFocusesSibling` (Today; the split stays with 2 panes and rescaled factors).
2. `cmdWOnPaneOfTwoCollapsesAndShowsSurvivorAsPlainTab` (already in `CloseTabTests`; extend it to the container being
   hidden).
3. `ctrlShiftMinusNeverArchives` (CF-18; `archived` empty, `ArchiveCoordinator.pendingItems` empty).
4. `autoArchiveExemptsEveryVisiblePane`. With a split shown and one pane idle past the threshold, `exempt()` contains
   both panes and the split is not archived.
5. `hiddenPanesGetLastActiveAtWhenCardSwitches` (decision 10; `markInactive` with both panes).
6. `terminationStampsAllVisiblePanes`, at the `AppSession` level, if it is testable there. Otherwise assert
   `visibleNodes` from the controller and rely on the existing `AppSession` line
   `source.markInactive(window.visibleNodes, at: .now)`.
7. `restoredSplitShowsWithItsLayout`: archive a split root through `ArchiveCoordinator`, restore it, activate it; the
   container shows the same factors and orientation.
8. `restoredPaneComesBackAsPlainTab` (`Archiver` default: top of Today).
9. Core, `ArchiverTests`: `archivedSplitWithMismatchedFactorsRestoresAndNormalizesOnShow`. This is a model-level
   restore keeping the stored factors as they are; the normalization is asserted in `SplitLayoutTests`.
10. `relaunchKeepsSplitLayout`: encode, then decode a `ModelSidebarSource` value after `setSplitWidthFactors`, then
    show the split. This is a GUI-light check; the persistence itself is covered by S1's round trip.

**Commit:** `Split View archive, restore and visibility rules covered end to end`

---

### Task S9: Frame-time gate for divider resize, and results

**Parity:** design section 5 (2), issue acceptance "Divider resize meets the frame-time gate".

**Files:**
- Create: `$KIT/Tests/ShellKitGUITests/FrameTestSupport.swift`. Move the private `FrameScript` and `StableFrames` out
  of `SpacePagerTests.swift` and make them `internal`; `SpacePagerTests` keeps passing unchanged.
- Create: `$KIT/Tests/ShellKitGUITests/SplitPacingTests.swift`
- Create: `docs/plans/2026-10-2x-split-view-results.md`

**Test design** (copies `testFramePacingDuringSwipeAndKeyboardSwitch`):
- **Window and engine.** A 1200x800 shell window and a split shown through `ShellWindowController` with
  `InMemoryEngine`, so the pane content views are plain NSViews and the test measures the shell's own frame work.
- **Warm-up.** `StableFrames.wait(on: container, count: 10, threshold: FrameStats().hitchThreshold)`.
- **Scripted drag.** `divider.beginDrag()`, then a `FrameScript` of 60 frames calling `divider.drag(to:)` with a sine
  sweep across the allowed range, then `divider.endDrag()`. Stats come from `container.lastPacing`.
- **Cases:** `split-divider-2`, `split-divider-4` (the middle divider), `split-divider-4-stacked`.
- **Gate:** `frameCount > 10`, and `hitchCount == 0` unless the 1-minute load average is at or above the active core
  count. The summary line and an `XCTAttachment` follow the exact format of `spacepager.pacing`.
- **FakeEngine run (informational, not gated).** The same script with `FakeEngine` panes loading a page from
  `LoopbackServer`. It prints `split-divider-webkit` and records the result. WKWebView `setFrame` work per frame may
  miss 8.6 ms (see Risks); the result decides whether decision 5 needs the fallback below before #33.
- **Commit-once check.** After the scripted drag, the source's `onDidChange` count is exactly 1.

**Steps**
1. Move the helpers, then run `SpacePagerTests` and expect them unchanged and passing.
2. Write `SplitPacingTests` and run it on an idle machine at 120 Hz (ProMotion or external 120 Hz). Record
   `screenMaxFPS` and the numbers.
3. Write the results file:
   - test counts against S0;
   - pacing numbers for the InMemoryEngine and FakeEngine runs;
   - which key-equivalent strings were used (S5);
   - the NEEDS-RUNTIME-CHECK rows still open (RT-06, RT-21, RT-22, RT-31..RT-38);
   - the deferred list.
4. Check the issue's boxes: BH-115..BH-128 implemented or explicitly deferred (cite the Deferred section),
   KB-070..KB-075 bound, gate met.

**Commit:** `Split divider frame-time gate and Split View results`

---

## Open questions (NEEDS-RUNTIME-CHECK)

| Question | Row | Default in this plan |
|---|---|---|
| Which `layoutOrientation` string Arc writes for side by side | RT-31 | `.horizontal` = side by side; only `SplitLayout.axis(for:)` changes if wrong |
| Drop zones and preview for drag-to-split; edge or center | RT-32, GS-011 | Decision 11 zones |
| Minimum pane size; whether only the adjacent panes resize; divider double-click | RT-33 | 240 pt, adjacent only, double-click equalizes |
| What Ctrl-Shift-= shows in the new pane | RT-34, KB-070 | The command bar in `.newSplitPane` mode |
| Pane shares after adding a pane | RT-35 | Equal shares |
| A Pinned split pane after Cmd-W | RT-36 | Placeholder; a click reopens |
| Gap, focus indicator, pane header controls ("Split Controls" button, X above a pane) | RT-37, BH-120, BH-121 | 10 pt gap, border emphasis; header controls deferred to a follow-up after measurement |
| Menu location and titles | RT-38 | View > Split View |
| Next / previous pane keys and direction | RT-06, CF-16 | Ctrl-Shift-] next, Ctrl-Shift-[ previous |
| Where a pane removed with Ctrl-Shift-- goes; Cmd-W in a split | RT-21, CF-18 | Right after the split, not archived; Cmd-W per user decision 4 |
| Opt-click on the Split Tab close button | RT-22, BH-127 | Deferred (flag-gated, needs #8) |

## Risks

1. **The engine view resize cost per divider frame.** The shell's frames are cheap, but FakeEngine's
   `WKWebView.setFrame` and later Chromium's `RenderWidgetHostView` resize do main-thread work and trigger a relayout
   in another process on every frame.
   - The S9 gate is measured with InMemoryEngine views, so it gates shell work. The FakeEngine run is recorded, and
     #33 must re-run the gate with ChromiumEngine.
   - Fallback if a real engine misses the gate: during the drag, keep each pane's engine view at its pre-drag size,
     anchored and clipped by its card (frames still move at 120 Hz). Resize engine views at most every other frame, or
     only on mouse-up. Arc's own behavior here is unknown (RT-33).
2. **Key equivalents with Shift.** Matching depends on the keyboard layout ("=" versus "+", "1" versus "!", "]" versus
   "}"). S5 tests the US layout and has a keyCode monitor fallback. Other layouts (German, French AZERTY, where these
   keys need Option or sit elsewhere) are not gated. Record them in the results file and open a follow-up issue.
3. **Drag destination order.** Engine views register for drags and sit under the pointer. The temporary overlay (added
   only during a sidebar drag) avoids that. If AppKit still routes to the web view, the fallback is to register the
   private type on `ShellRootView` and compute zones from root coordinates.
4. **Mutation during change delivery.** Re-showing a split from a sidebar change calls `replay`, then
   `sidebar.updateTab`. Every re-show triggered by a change is deferred one main-queue turn (the
   `activateRestoredTabLater` pattern). The S4 tests cover a separate, orientation and width change while the split is
   shown.
5. **Merge conflicts in `ShellWindowController`.** #33 (ChromiumEngine) and other open shell work touch window wiring.
   The split code goes into `ShellWindowController+Split.swift`, and the shared file changes stay small
   (`show(node:)`, `visibleNodes`, `validateMenuItem`, `handle(_:)`).
6. **Imported or older splits whose factors do not match their panes.** These are handled by `SplitLayout.normalized`
   at display time. The model is never rewritten silently; the first divider commit stores normalized factors.
7. **First responder with Chromium.** `makeFirstResponder(contentView)` works with WKWebView. Chromium's view may need
   its own focus call. That is listed for #33 (a possible `EngineClient.focus(_:)` plus an `EngineContract` rule), not
   added here.
8. **Accessibility.** Pane cards and dividers need accessibility roles (`AXSplitGroup`, `AXSplitter` with a value).
   This is not in a parity row; add the roles in S3 (divider: `setAccessibilityRole(.splitter)`, value = factor) so
   the design section 5 accessibility-driven parity tests can drive splits later.

## Critical files for implementation

- `app/ArktCore/Sources/SidebarModel/SidebarModel.swift` (and the new `Sidebar+Split.swift` next to it)
- `app/ArktShell/ShellKit/Sources/ShellUI/Sidebar/SidebarSource.swift`
- `app/ArktShell/ShellKit/Sources/ShellUI/Window/ShellWindowController.swift` (and the new
  `ShellWindowController+Split.swift`)
- `app/ArktShell/ShellKit/Sources/ShellUI/Window/ContentCardView.swift` (reused as the pane card by the new
  `Split/SplitContainerView.swift`)
- `app/ArktShell/ShellKit/Sources/CoreBridge/ModelSidebarSource.swift`
