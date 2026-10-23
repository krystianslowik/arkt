---
name: Chromium rebase
about: Move the Chromium pin to a new tag (security release or milestone), following engine/REBASE.md
title: "Rebase: Chromium <new tag>"
labels: ["type:chore", "area:engine", "area:release", "status:triage"]
assignees: []
---

## Context

<!-- Old tag -> new tag. Kind: security (same MAJOR.MINOR.BUILD) or milestone. Chrome release date and link to the
Chrome Releases post. Deadline for a security release: release date + 7 days. -->

- From: 
- To: 
- Kind: 
- Chrome release date: 
- Deadline: 

## Depends on

None

## Acceptance criteria

Steps and commands: `engine/REBASE.md` (section numbers in brackets).

- [ ] Announced "Exporting patches now" here and on every open engine pull request (3)
- [ ] `$CR` clean, Apply guard passes, overlay link checked, disk and swap recorded (3)
- [ ] `arkt` saved as `arkt-<old tag>`, new tag fetched, patches applied; conflicts and dropped patches listed (4)
- [ ] `gclient sync --revision src@refs/tags/<new tag>` done; `chrome/VERSION` equals the new tag (4)
- [ ] `PIN` set in `engine/README.md`; Export done; patch files and `.patches` committed (4)
- [ ] `out/Spike` and `out/Arkt` built with no `FAILED:` lines; overlay fixes listed (5)
- [ ] Patch budget gate passes; budget table updated (6)
- [ ] Verification (7): version; W5b matrix (fast path: scenarios 1-8); W5c visibility (full path); Web Store
      install; extension popup; UA and `Sec-CH-UA` brands with no Arkt token, `_ChromeMain` = 1; keychain string;
      embedding (full path); 120 Hz (full path); 1Password once #23 records a GO; no processes left
- [ ] Re-signed (notarized and stapled once #125 lands); previous bundle saved; new bundle installed and checked (8)
- [ ] Rebase log row with times and disk (10)
- [ ] Pull request open with the results; backup branch and saved bundle kept until the next rebase

## Plan

`engine/REBASE.md`. Maintainer steps (1Password, keychain item if patch 0003 changed) go under "Needs the user".

<!--
Triage (maintainer): set status:ready and an order label the same day; a security rebase has a 7-day deadline.
-->
