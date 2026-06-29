# Changelog

All notable changes to GSMTools are tracked here.

The project uses pre-1.0 SemVer. Breaking workflow changes can still happen before `1.0.0`.

## Unreleased

### Added

- App icon asset with transparent outer background and `.app` bundle wiring.

## 0.1.0 - V0 Review Build

Initial release-candidate build for local review.

### Added

- Native SwiftUI macOS app scaffold.
- Settings window with Keychain-backed API token storage.
- Customer API project/device loading.
- Cross-project transmitter cohort selection.
- Run builder for all-data, specific-period, last-X-days, comparison, deployment, and config-update analysis modes.
- Local SQLite run, group, alert, and report persistence.
- Telemetry pull runner with persisted progress.
- Device cohort timeline and transmitter drill-down views.
- GPS fix yield, fix time, connection, solar, battery, and ACC/activity summaries.
- Battery recharge recovery screen.
- GPS versus cell-locate map with marker toggles and latest-fix zoom.
- Report and alert summary screens.
- Markdown/PDF/CSV report export support in the core reporting layer.
- App version files and bundle version wiring.

### Fixed During V0 Stabilization

- Distinguish snapshot metadata from pulled telemetry.
- Use consistent evidence windows for metric values, lifeline timelines, map samples, and drill-down panels.
- Use observed telemetry bounds for all-data run display instead of the synthetic API pull start date.
- Replace ambiguous `GPS none` device-row text with `GPS not in snapshot`.

### Known Gaps

- No signed/notarized distribution package yet.
- No device configuration push workflow.
- Behavior alert authoring is not production-ready.
- Existing local runs from earlier development builds may need to be rerun for corrected timeline summaries.
