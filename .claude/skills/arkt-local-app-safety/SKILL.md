---
name: arkt-local-app-safety
description: Use before launching, testing or driving a local Arkt build (app copies, engine bundles, UI tests, synthetic input) - keep test builds away from the user's real apps, links, browser data and processes, and clean up after.
---

# Arkt local app safety

Local runs share the machine with the user's real browser and apps. Keep test builds isolated and leave nothing
behind. These rules hold for every launch, test run and build.

## 0. Gate: write it down before launching

1. What you will launch, from which path, under which bundle id.
2. The throwaway data folder or profile it will use.
3. How you will record its PID and stop it.
4. Free disk now (`df -h .`).

**STOP** if the bundle id equals an installed release build's, or the data folder is a real profile.

## 1. Checklist

1. **Own bundle id.** Launch app copies under their own bundle id, distinct from any installed release build.
2. **No LaunchServices registration** under the real app's bundle id (`lsregister`, or copying a test bundle into
   `/Applications`). A test build registered that way takes over the user's link opens.
3. **Launch by path** inside the build output, not by bundle id.
4. **Exact PID only.** Record the PID of everything you start (`$!`) and stop it with `kill <PID>`. Never `pkill`,
   `killall`, or a name or pattern. Never stop a process you did not start (`CONTRIBUTING.md`, section 7).
5. **Input only into your own window.** Before each synthetic click or key, check the frontmost app is your test
   build. **STOP** if it is not.
6. **No real browser data.** Never open, copy, read or grep the user's browser data or profiles. Tests use synthetic
   fixtures and the throwaway folders the harness creates. Engine launches use a throwaway `--user-data-dir` and
   `--use-mock-keychain` (`engine/README.md`, "Launch flags").
7. **Never bypass** a blocked permission prompt, a hook or a sandbox. If one blocks you, stop and report it.
8. **Disk.** Check free space before any build. **STOP** if it is short; never delete files you did not create.

## 2. Cleanup, verify before you claim

1. Stop every process you started; confirm with `ps -p <PID>` (prints no process).
2. Remove the throwaway profiles and data folders your run created.
3. UI-test attachments land outside the repo; where they are and how to clear them is in `CONTRIBUTING.md`,
   section 7, "Attachments". Keep the `deleteOnSuccess` lifetime on any attachment you add.
4. Report what you stopped and removed, and anything you kept and why.

## Common mistakes we made

- UI tests keeping screenshots for passing runs until the disk filled (#426, fixed in #427).
- A test build registered under the real bundle id, which took over the user's link opens.
