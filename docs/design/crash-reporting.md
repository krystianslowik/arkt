# Crash reporting

Issue #129 (app half; engine-process capture is #447). Opt-in, local, and never carrying URLs or titles.

## Decisions (maintainer, on #129)

- No third-party crash service and no network upload. Reports are stored on this Mac, at most 20, for 30 days.
- With consent, Send Crash Report opens a prefilled issue on the project's GitHub repository in the browser. The user
  reviews it and submits it; Arkt sends nothing itself. An upload endpoint is decided before beta, with signing (#125).
- One switch, Settings > Privacy > Send crash reports, off by default. Onboarding does not ask.
- After the first crash, the next launch asks once: "Arkt quit unexpectedly. Send a report?" with Send, Don't Send and
  Always Send. Any answer ends the ask for good. Always Send turns the switch on.

## How it works

| Part | Where | What it does |
|---|---|---|
| Capture | `App/CrashCapture` | MetricKit: each `MXCrashDiagnostic` MetricKit delivers on a later launch becomes a report. An uncaught `NSException` handler writes a report as the process goes down. The handler chains to the one installed before it, once. AppKit usually catches exceptions on the main run loop before they reach it, so it mostly covers throws off the main thread; MetricKit covers the rest. No signal handler: MetricKit captures signal crashes out of process, and a handler that allocates or writes files inside a signal is unsafe. |
| Duplicates | `CrashReportRecorder` | An uncaught exception ends in SIGABRT, which MetricKit also reports. The first MetricKit abort after an exception report is the same crash and is dropped. |
| Stripping | `CrashReporting.CrashReportStripper` | The report is built field by field, so only allowed fields exist. Strings in it are scrubbed too. |
| Storage | `CrashReporting.CrashReportStore` | `<data folder>/CrashReports/<crash id>.json`, one file per report, stripped before it is written. At most 20; none older than 30 days (counted from the crash, with an injected clock in tests). |
| Consent | `CrashReportPolicy` | Switch on: reports are stored. Switch off and not asked yet: only the newest report is held, for the ask. Switch off and asked: nothing is stored. Turning the switch off deletes every stored report and settles the ask, so it does not come back. |
| Hand-off | `GitHubIssueLink` | Builds the issue URL. A long stack is cut from the bottom, and the issue body says "Stack truncated: showing N of M frames", so the URL stays under 7000 characters. |

## What a report holds

Reports are stored with owner-only permissions (folder 0700, files 0600).

Kept: OS version, architecture, app version and build, engine version, a random crash ID, the exception type (Mach
exception and signal, or the `NSException` name when it is an identifier of letters, digits, dots and underscores up to 64 characters, else `CustomException`), and the stack: image name, offset into the image, symbol when the
runtime gave one, and each image's build UUID.

Stripped:

| Forbidden | How |
|---|---|
| URLs | Never copied from the exception reason or annotations; any `scheme://`, `mailto:` or `www.` text in a kept string becomes `<url>` |
| Page titles, profile names, Space names | The exception reason and all annotations are dropped, never read into a report; the current profile and Space names, read from the sidebar at each report, are redacted wherever they appear |
| File paths | Home becomes `~` and the rest of the path is dropped; any other absolute path becomes `<path>`; an image keeps only its file name |
| User names | Removed wherever they appear |
| Extension IDs | Any 32-letter a-p ID becomes `<extension>` |

## Symbolication

MetricKit delivers image names, offsets and build UUIDs, not symbol names. A report from a build whose dSYM is kept can
be symbolicated by UUID: `atos -o <dSYM>/Contents/Resources/DWARF/ArktShell -arch arm64 -l <load address> <offset>`
(offsets are into the text segment, so the load address is the segment start). `NSException` stacks arrive symbolicated
by the runtime.

## Tests

`CrashReportingTests` (stripping with every forbidden field seeded, retention with an injected clock, the consent gate
and the one-time ask, MetricKit mapping, the GitHub URL length limit), `IsolationTests` (the target imports only
Foundation, only the app links it, the app's capture imports no Persistence), `AppSettingsTests`,
`DialogContentTests`, and in the GUI suite `CrashReportSettingsTests` and `DialogTests`.
