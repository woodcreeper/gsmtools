# GSMTools

GSMTools is a native macOS app for evaluating GPS/GSM telemetry transmitter performance from the CTT customer API.

V0 is a read-only analysis workstation. It helps an analyst build transmitter cohorts, pull telemetry for a defined evidence window, compare transmitter performance, inspect per-device lifelines, and export review material. It does not push device configuration.

## Status

- Current version: `0.1.0` build `1`
- Platform: macOS 14+
- UI: SwiftUI
- Package manager: Swift Package Manager
- Local database: SQLite via GRDB
- API: CTT customer API
- API base URL: `https://us-central1-ctt-data-portal.cloudfunctions.net/customerApi/v1`
- API spec: `https://us-central1-ctt-data-portal.cloudfunctions.net/customerApi/v1/openapi.json`

## What V0 Does

GSMTools is built around the analyst flow:

1. Load accessible projects with the current API token.
2. Select transmitters from one or more projects.
3. Save a cohort when that transmitter set will be reused.
4. Start a run from the Runs screen by choosing the question, scope, and data period.
5. Review results in Devices, where transmitters are ranked by the selected metric.
6. Drill into a transmitter to inspect GPS, fix time, connections, solar, battery, and activity evidence.
7. Export summaries from Reports.

V0 supports these analysis modes:

- All available data
- Specific period
- Last X days summary
- Compare two custom periods
- Last X days versus the prior X days
- Since deployment
- Pre/post deployment
- Since config update versus before

Deployment-aware modes use deployment timestamps exposed by the API for each transmitter when available.

## Metrics

The app currently screens and summarizes:

- GPS fix yield
- GPS fixes versus cell-locate fixes
- GPS failure rate when a denominator can be inferred
- Median time-to-fix
- GPS fix cadence
- Connection check-ins
- Check-in cadence
- Connection failure rate when the API exposes enough status fields
- Solar exposure
- Solar voltage/current where exposed
- Median battery voltage
- Battery voltage trend
- Battery discharge/recharge recovery pattern
- Reset count from uptime drops
- Mean activity
- Activity load from cumulative counters or observed activity samples
- Temperature where exposed

The Devices screen uses a consistent evidence window for metric values, lifeline timelines, map samples, and drill-down panels. Pull range and evidence window are intentionally separate: the API may pull a broad range, but the UI should state and visualize the data window used for the selected metric.

## Interpreting Current V0 Screens

### Projects

Projects is for discovery and cohort building. It shows project/device snapshot metadata from the project endpoint. Snapshot text such as `GPS not in snapshot` means the project-device list did not expose a latest location timestamp. It does not prove that the transmitter has no GPS telemetry; run an analysis or pull samples to inspect actual telemetry records.

### Runs

Runs is where analysis starts. A run stores:

- selected projects/transmitters
- selected question/mode
- evidence window and optional reference window
- retention mode
- run progress and status
- generated device summaries

Changing scope, question, or period creates a new run. Existing run results remain available until deleted.

### Devices

Devices is the primary interpretation surface. It has two modes:

- Cohort: compare many transmitters on one shared axis.
- Transmitter: drill into one transmitter and inspect the evidence behind each metric.

For comparison runs, labels use `current` and `reference`. For single-period runs, labels use `current period` or `current only`; those are absolute screens, not decline tests.

### Fix Map

The fix map shows mapped fixes from the selected evidence window:

- GPS fixes are green.
- Cell-locate fixes are blue.
- The GPS and Cell-locate toggles control which marker types are visible.
- Latest zoom targets the latest visible fix type. If only GPS is visible, it zooms to the latest GPS fix; if only Cell-locate is visible, it zooms to the latest cell-locate fix.
- Clicking a point opens timestamp and metadata.

### Alerts

Alerts are generated from completed runs. In V0 they are threshold screens and behavior candidates, not final biological classifications.

### Reports

Reports are exportable summaries of completed runs. Device-level ranking and investigation still live primarily in Devices.

## Data And Privacy

- The app stores one API token in macOS Keychain.
- The token is never intentionally logged.
- Project and device visibility comes entirely from the token's API permissions.
- Raw telemetry cache and analysis history are stored locally.
- V0 has no server-side runner and no cloud sync.
- Runs can be deleted from the local database.

## Requirements

- macOS 14 or later
- Xcode command line tools
- Swift 5.9 or later
- Network access to the CTT customer API
- A valid CTT customer API token

Install command line tools if needed:

```bash
xcode-select --install
```

## Build And Run

From the repository root:

```bash
swift build
swift test
./script/build_and_run.sh --verify
./script/build_and_run.sh
```

`script/build_and_run.sh` stages a local `.app` bundle in `dist/GSMTools.app`, writes bundle metadata, and launches it as a normal macOS app.

Supported script modes:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Versioning

GSMTools uses pre-1.0 SemVer plus a monotonically increasing bundle build number.

- `VERSION` contains the marketing/version string, for example `0.1.0`.
- `BUILD` contains the app bundle build number, for example `1`.
- `script/build_and_run.sh` writes those values into `CFBundleShortVersionString` and `CFBundleVersion`.
- Settings displays the version from the running app bundle.

Use the version helper:

```bash
./script/version.sh show
./script/version.sh bump patch
./script/version.sh bump minor
./script/version.sh bump major
./script/version.sh bump build
./script/version.sh set 0.2.0
```

Suggested release convention:

- `0.1.x`: V0 stabilization and bug fixes.
- `0.2.x`: new V0-era feature sets, such as behavior-rule authoring.
- `1.0.0`: first production release with stable workflows, packaging, signing, and documented customer support expectations.

## Release Checklist

Before pushing or tagging:

```bash
./script/version.sh show
swift build
swift test
./script/build_and_run.sh --verify
```

Then manually check:

- Settings shows the expected version/build.
- Projects loads with an API token.
- Cross-project cohort selection still shows selected project counts.
- Runs can create and complete a new analysis.
- Devices shows the latest completed run and states the evidence window.
- GPS/Fix/Connection timelines agree with the selected evidence window.
- Fix map toggles and latest zoom work.
- Reports and Alerts open without placeholder-only content.
- No token or customer data appears in logs.

## Repository Layout

```text
Sources/GSMTools/
  App/                  App entry point and app-wide state
  Views/                SwiftUI screens
  Support/              UI design helpers, formatters, version display

Sources/GSMToolsCore/
  Analysis/             Metrics, baselines, behavior screens
  Models/               API and run models
  Reporting/            Export generation
  Services/             API, Keychain, scheduler, pull runner
  Stores/               SQLite persistence
  Support/              JSON and timestamp utilities

Tests/GSMToolsCoreTests/ Core unit and integration-style tests
script/                 Local build, run, and version scripts
```

## Known V0 Limitations

- No device configuration push workflow.
- Scheduled checks run only while the app is open.
- Behavior classification is early-stage. Nesting and mortality-style workflows need explicit rule authoring, validation, and review UI before they should be treated as operational alerts.
- Reports are summaries, not a full replacement for the Devices drill-down.
- Existing saved runs generated by earlier development builds may contain stale summary buckets. Rerun analyses after upgrading when timeline consistency matters.
- The local `.app` bundle is unsigned and not notarized.

## Reviewer Notes

For code review, start with:

- `Sources/GSMTools/App/AppModel.swift`
- `Sources/GSMTools/Views/RunBuilderView.swift`
- `Sources/GSMTools/Views/LifelineWorkspaceView.swift`
- `Sources/GSMTools/Views/ProjectBrowserView.swift`
- `Sources/GSMToolsCore/Analysis/MetricCalculator.swift`
- `Sources/GSMToolsCore/Models/RunModels.swift`

High-value review questions:

- Does every displayed metric trace back to the same evidence window stated in the UI?
- Does the UI avoid implying more certainty than the data supports?
- Are snapshot fields clearly distinguished from pulled telemetry?
- Are comparison labels and current-only labels unambiguous?
- Are threshold screens clearly framed as screens rather than validated biological or hardware diagnoses?
