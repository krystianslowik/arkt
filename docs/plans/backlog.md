# Backlog

Items found outside a track plan. Pull into a track when scheduled.

## App shell

- **Sidebar URL bar (Arc parity).** Arkt shows no current URL anywhere. Arc shows the active tab's URL (host,
  compact) in a pill at the top of the sidebar, under the traffic lights. Clicking it opens the command bar
  prefilled with the URL (same as KB-002 Cmd-L); right-click offers show/hide Toolbar (BH-031, GS-042); with the
  Toolbar shown (Toggle Toolbar, Cmd-Shift-D) the content card gets a top bar with back/forward/reload and the
  full URL. Needs: URL pill view in SidebarContainerView top bar, engine urlChanged binding, toolbar toggle +
  persisted setting, parity rows KB/BH/GS above, tests. Measure/screenshot Arc for exact layout (RT item).
- **Hover close (X) on sidebar rows (Arc parity).** No way to close a tab with the mouse. Arc shows an X at the
  trailing edge of a row on hover (GS-043): on a Today tab it archives ("Archive this tab", BH-071); on a pinned
  tab it closes the page and keeps the pin ("Close and Keep Pinned", BH-067/BH-070, NEEDS-RUNTIME-CHECK RT-17);
  Opt-click on a split's X unsplits (BH-127, flag-gated). Needs: trailing button in SidebarTabCellView shown on
  row hover (fades with the row state), tooltip text per kind, VoiceOver action, wiring to the Track E archive /
  close paths (E5b Cmd-W uses the same actions), tests. Depends on E5a/E5b.

## Engine and web compatibility

- **User agent must match current Chrome.** The shell test build (FakeEngine, WKWebView) sends
  `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)` with no
  `Version/... Safari/...` token, so Google and others serve their legacy page. Requirements: the Chromium engine
  ships Chromium's stock Chrome UA for its milestone (`... Chrome/156.0.0.0 Safari/537.36`, reduced UA format) plus
  matching UA Client Hints (`Sec-CH-UA` brands "Chromium"/"Google Chrome"-compatible list, no "Arkt" token that
  sites could sniff), kept in sync on every Chromium rebase; check the brand list Arc sent for parity. For the
  FakeEngine dev build, set `customUserAgent` to a current Safari UA so test pages render normally. Verify with
  google.com, a UA echo page and `navigator.userAgentData` in a test.
  Status: the FakeEngine part is done (`Version/<installed Safari version> Safari/605.1.15` via
  `applicationNameForUserAgent`, unit and GUI tests); the engine rules and rebase checks are in `engine/README.md`
  ("Web identity") and run in week-2 Tasks W2 and W10.
