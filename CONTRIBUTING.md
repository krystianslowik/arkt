# Contributing to Arkt

Thanks for helping. A few rules keep the history clean and the app fast.

## Workflow

- **One GitHub issue per backlog item.** Every piece of work starts as an issue (see `docs/plans/backlog.md` for the
  current backlog). Discuss scope there before writing code.
- **One pull request per issue.** Keep each PR focused on its issue and reference it (`Fixes #123`).
- **TDD.** Write the test first, run it and watch it fail (a compile error counts), implement, run it again.
  Pure logic goes into Swift Testing tests; anything that opens windows goes into `ShellKitGUITests`.
- **Pathspec commits.** Stage explicit paths (`git add <paths>`); never `git add -A` or `git add .`. Plain,
  descriptive commit messages.

## Code

- **Shell: zsh.** Commands in docs and scripts are written for zsh.
- **No emojis in code**: not in sources, comments, logs, fixtures or commit messages.
- Swift 6 language mode with complete concurrency checking. Fix concurrency diagnostics at the root; no
  `@unchecked Sendable` or `nonisolated(unsafe)` in production code.
- Hot paths (sidebar, command bar, window chrome) are AppKit + Core Animation, not SwiftUI lists or Auto Layout.
- Upstream Chromium changes live only as patch files in `engine/patches/chromium`; follow the workflow in
  `engine/README.md`.

## Before opening a PR

```zsh
cd app/ArktCore && swift test
cd app/ArktShell/ShellKit && swift test --skip ShellKitGUITests
```

Run the GUI tests (`swift test --filter ShellKitGUITests`) locally too when you touch the shell UI.

## Privacy

Test fixtures are synthetic. Never commit real browsing data, Arc data, titles, URLs, credentials or signing
identities.
