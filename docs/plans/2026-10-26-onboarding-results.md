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
