# Release Checklist

Use this checklist before pushing a V0 tag.

## Automated

```bash
./script/version.sh show
swift build
swift test
./script/build_and_run.sh --verify
```

## Manual Smoke Test

- Launch `dist/GSMTools.app`.
- Confirm Settings shows the intended version/build.
- Save or verify the API token without exposing it in logs.
- Load projects.
- Load devices for at least one project.
- Select transmitters across more than one project and create a cohort.
- Start a current-only run.
- Start a comparison run.
- Open Devices and verify the run selector uses the expected run.
- Confirm timeline labels match the evidence window stated in the UI.
- Confirm GPS, Fix, and Conn views use the same evidence window.
- Confirm fix map marker toggles and latest-fix zoom work.
- Open Reports and Alerts.
- Delete a test run and confirm it disappears.

## Release Steps

1. Update `VERSION` and `BUILD` through `script/version.sh`.
2. Update `CHANGELOG.md`.
3. Run the automated checks.
4. Run the manual smoke test.
5. Commit the release state.
6. Tag with `v$(cat VERSION)`.
7. Push branch and tag after review.

## Do Not Release If

- Any metric screen mixes pull range and evidence window.
- Snapshot fields are presented as telemetry conclusions.
- Token values appear in terminal output or logs.
- The app cannot complete a fresh run against live data.
- A report or alert screen is still placeholder-only for completed runs.
