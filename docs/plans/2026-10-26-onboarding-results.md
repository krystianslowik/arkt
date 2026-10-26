# Onboarding results (#310)

Spec: `docs/design/onboarding.md` (design #303, Hero direction). Issue: #310. One section per pull request; each
appends its own section and never rewrites another's numbers.

## PR 1: the flow, with the Core Animation stage

Split chosen: PR 1 is the whole flow with a no-particle stage behind the `OnboardingStage` protocol (spec section
7.4, "No particle layer"); PR 2 adds the Metal particle field behind the same protocol.

### What is built

| Area | Where |
|---|---|
| Brand tokens `brandTextPrimary`, `brandTextSecondary`, `brandTextSecondaryContrast`, `brandHairline`, `brandHairlineContrast`, `brandControlFill`, `brandControlFillPressed` | `ShellUI/Theme/BrandTokens.swift`, `BrandTokensTests` |
| Six theme families, Dune first and the default, measured by `ShellTokensContrastTests` | `ShellUI/Sidebar/SpaceCatalog.swift`, `SpaceThemeFamilyTests` |
| `BrandType`: Avenir Next by PostScript name, system-font fallback, per-size tracking, fixed line heights placed the CSS way | `ShellUI/Theme/BrandType.swift`, `BrandTypeTests` |
| `gather` spring preset (0.88, 0.80 s) | `Motion/SpringPreset.swift` |
| Flow model: branches, step lists, progress, footer, Return and Escape per step, arrow history, resume snapshot | `ShellUI/Onboarding/OnboardingFlow.swift`, `OnboardingFlowTests` |
| Make it yours as a value (swatches, Imported / Current, appearance, name, Skip restore) | `OnboardingTheme.swift` |
| Final copy, plural rules, announcements; no string names Arc | `OnboardingCopy.swift`, `OnboardingCopyTests` |
| Read-only count pass, `ArcImportOutcome.addedSpaces` | `CoreBridge/ArcImportCount.swift`, `ArcImportCountTests` |
| Views, controller, Core Animation stage, mark from the artwork | `ShellUI/Onboarding/*`, `ShellKitGUITests/OnboardingTests` |
| App: record in the profile's settings, services, first-run gate, Help > Welcome to Arkt, default browser, links from other apps | `App/AppOnboarding.swift`, `AppComposition`, `AppSession`, `AppCommands`, `MainMenu`, `AppDelegate`, `project.yml` |
| UI tests: both branches to the browser, Skip setup, Name field Escape, arrows, no "Arc", Help menu | `UITests/OnboardingTests.swift` |

### Measurements

| Check | Value |
|---|---|
| `brandHairlineContrast` light, graphite at 45 % (spec) | 2.73:1 on porcelain, below 3:1; shipped at 50 %: 3.13:1 |
| `brandTextSecondaryContrast` | 9.99:1 light, 12.58:1 dark (the spec lists 10.1 / 12.9; the hex values are kept) |
| Blossom light end stop #F29BBB (sRGB) | `secondaryText` light 4.496:1 and `sidebarForeground` light 2.98:1 at 0.64 / 0.48; raised to 0.65 / 0.49 |
| Mark samples at 140 px (alpha > 200, saturation > 70) | within 300 of the spec's 6,622 (`BrandMarkArtworkTests`) |

## PR 2: the Metal particle field

### What is built

| Area | Where |
|---|---|
| Formations from the live layout (mark, fold, counts, theme, default, ext, tour 1 to 5, done, card, field), lanes of index mod 20, the website's spring model, re-tint at 900 pt/s, retarget without restart, the section 9 floors | `ShellUI/Onboarding/Particles/ParticleFormationBuilder.swift`, `ParticleSamplers.swift`, `ParticleFormationTests` |
| Compute kernel and point-sprite draw, compiled at run time from source (no Metal build step in the package) | `ParticleShaders.swift`, `ParticleRenderer.swift` |
| `MetalOnboardingStage`: `CAMetalLayer` view, display link at up to 120 Hz, tiers, pause, fold and release | `MetalOnboardingStage.swift`, `ParticleFieldTests` |
| Default stage: Metal when it runs, else the Core Animation stage of PR 1 | `ShellWindowController+Onboarding.swift` |

### Measurements

Machine: Apple M2 Pro (10 cores), macOS 27.0, built-in display at 120 Hz. Not measured on an M1 (none available).

| Check | Value |
|---|---|
| Full tier, 20,480 motes, Welcome formation, 2240 x 1440 drawable, 240 frames (`ParticleFieldTests.testFrameBudgetAt2x`, command buffer GPU timestamps) | GPU median 0.41 ms, p95 1.79 to 2.53 ms over two runs (first frames and other worktrees' load); CPU encode median 0.05 to 0.12 ms |
| Budget (spec, M1) | GPU at most 1.0 ms, CPU at most 0.3 ms: met on this machine at the median |
| Mark samples at 140 px | as PR 1 |

Metal System Trace was not recorded; the GPU times above come from the command buffers' `gpuStartTime` / `gpuEndTime`, and each display-link callback is a `particles.frame` interval in `ShellSignposts` for Instruments.

## #375: Imported copy, fallback window, footer fade

Maintainer decisions after the PR 1 and PR 2 review notes, recorded as decisions 10 to 12 in the spec.

| Change | Where |
|---|---|
| Imported note: "All of it came over. Your other browser stays as it is." only with nothing skipped; otherwise "Most of it came over. {n} items couldn't be imported." | `OnboardingCopy.importedNote`, `OnboardingCopyTests`, `ShellKitGUITests/OnboardingTests.testImportedNoteSaysAllOrMostByWhatFailed` |
| Fallback tier when 30 of the last 60 frames are over 2 ms of GPU time: a 60-bit window, newest frame in bit 0, no allocation | `ParticleRenderer.GPUBudgetWindow`, `MetalOnboardingStage`, `ParticleFallbackTriggerTests` |
| Footer (Back, "N of 6", Skip setup) fades out with the content as the fold begins: 160 ms strong ease-out, text kept while it fades, buttons and VoiceOver off at once; under Reduce Motion it goes at once | `OnboardingView.concealFooter`, `OnboardingController.finish`, `ShellKitGUITests/OnboardingTests.testFooterFadesOutAsTheFoldBegins`, `testFooterGoesAtOnceUnderReduceMotion` |

Before, the finish hid the footer through the step-change path: a 250 ms fade, with the progress text blanked in
the same frame instead of fading.
