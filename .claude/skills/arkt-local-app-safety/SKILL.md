---
name: arkt-local-app-safety
description: Use before launching, testing or driving a local Arkt build (app copies, engine bundles, UI tests, synthetic input) - keep test builds away from the user's real apps, links, browser data and processes, and clean up after.
---

# Arkt local app safety

Local runs share the machine with the user's real browser and apps. Keep test builds isolated and leave nothing
behind.

## Bundle ids and LaunchServices

- Launch app copies under their own bundle id, distinct from any installed release build.
- Never register a build under the real app's bundle id with LaunchServices (`lsregister`, or copying a test bundle
  into `/Applications`). The test build then takes over the user's link opens and default-browser handling.
- Launch a test build by its path inside the build output, not by bundle id.

## Processes

- Record the PID of everything you start (`$!` after a background launch) and stop it by that exact PID:
  `kill <PID>`.
- Never `pkill`, `killall` or kill by name or pattern (`CONTRIBUTING.md`, section 7, "Processes"). Never stop a
  process you did not start.

## Input

- Send synthetic input (clicks, keys, scrolls) only into a window your run owns, and only while it is frontmost.
  Check the frontmost app before every input step; stop if it is not yours.
- Keep hands off the keyboard and mouse while UI tests run (section 7).

## Browser data

- Never open, copy, read or grep the user's browser data or profiles. Tests use the synthetic fixtures and throwaway
  data folders the harness creates.
- Engine launches use a throwaway `--user-data-dir` and `--use-mock-keychain` (`engine/README.md`, "Launch flags").

## Cleanup

- UI-test attachments land outside the repo, in testmanagerd's container. Where they are and how to clear them is in
  `CONTRIBUTING.md`, section 7, "Attachments". Keep the `deleteOnSuccess` lifetime on any attachment you add.
- Remove throwaway profiles and data folders your run created.

## Disk

Check free disk before any build and stop if it is short:

```zsh
df -h .
```

Chromium builds need the space listed in `engine/README.md`. A build stopped for space is recorded in the results
file, never fixed by deleting files you did not create.
