> ## Instructions for Codex
>
> You are fixing verified code-review findings in a SwiftUI macOS app (GSMTools V0, untracked working tree).
>
> **Order of work:**
> 1. **Fix #1–#4 first** — these are smoke-test blockers (a freeze, two cases of silent data loss / unhonored limits, and a credential-exposure security bug). Do these before anything else.
> 2. **Then #5–#6** — cheap fixes that will hit real CTT data (optional fields, unknown deployment timestamps).
> 3. **Then #7–#10** — metric-accuracy issues; correct but lower urgency.
> 4. **The "Below-cap cleanup / reuse" appendix is OPTIONAL** — only touch it if explicitly asked; do not let it expand the scope of the core fixes.
>
> **Rules:**
> - Each finding is independent — fix them as separate, minimal changes. Do not refactor beyond what the finding describes.
> - Line numbers reflect the working tree at review time and may have drifted; locate each issue by the symbol/code snippet in the finding, not the line number alone.
> - `PLAUSIBLE` findings (#8, #9) depend on CTT API response shape — confirm the described data condition is real before changing behavior; if uncertain, prefer making the metric indeterminate over silently wrong.
> - After each fix, run `swift build` and `swift test` (30 tests baseline). Do not mark a finding done until both pass.
> - Match the surrounding code's style and conventions; do not introduce new dependencies.

# GSMTools V0 — Code Review Findings

Source: workflow-backed code review (high effort), 8 finder angles + 36 independent verifiers.
Target: entire untracked working tree (`Sources/`, `Tests/`) — SwiftUI macOS app, CTT API + Keychain + SQLite.
Result: 10 findings survived verification (8 CONFIRMED, 2 PLAUSIBLE). 12 candidates refuted; ~11 cleanup items below severity cap.

Each finding below is independent. Line numbers are from the current working tree. Fix in priority order; #1–#4 are the smoke-test blockers.

---

## 1. Infinite pagination loop on a non-advancing cursor — CONFIRMED — Critical
**File:** `Sources/GSMToolsCore/Services/CTTAPIClient.swift:170` (loop body ~160–174)

`fetchAll` runs `repeat { ... cursor = envelope.pagination?.hasMore == true ? envelope.pagination?.nextCursor : nil } while cursor != nil`. The only termination condition is `cursor == nil`. There is **no max-page cap** and **no check that `nextCursor` advanced** from the previous page.

**Failure:** If the CTT API ever returns `hasMore=true` with a repeating/non-advancing `nextCursor` (server bug or stuck cursor), `allProjects`/`allLocations`/`allSensors`/etc. never terminate. The telemetry pull hangs indefinitely, the run is stuck at "Running analysis…", and the app appears frozen with no way to cancel.

**Fix direction:** Track the previous cursor and break if `nextCursor == previousCursor`; add a hard max-page guard.

---

## 2. "Full telemetry" retention mode persists nothing — CONFIRMED — Critical
**File:** `Sources/GSMTools/App/AppModel.swift:870`

The UI exposes a "Full telemetry" retention option and `PullEstimator` branches on two retention modes, but `executeRun` only calls `recordRawCacheMetadata(runId:bundles:)` — which stores record counts and byte estimates — and then discards `outcome.bundles`. No branch on `retentionMode` ever persists the raw records.

**Failure:** A user who selects "Full telemetry" expecting raw locations/sensors/connections kept for later export or re-analysis ends up with no raw records in the database — silent loss of exactly the data they asked to retain.

**Fix direction:** When `retentionMode == .fullTelemetry`, persist the raw bundle rows (not just metadata) before discarding.

---

## 3. Disk budget computed but never enforced — CONFIRMED — Critical
**File:** `Sources/GSMTools/App/AppModel.swift:855`

`PullEstimate.exceedsDiskBudget` is computed (`bytes > diskBudgetBytes`, `PullEstimator.swift:41`; set at `RunModels.swift:777,786,794`) but is **never read** in any guard or UI warning. `executeRun` proceeds unconditionally and pulls every device's full telemetry into memory (`outcome.bundles`).

**Failure:** When a large cohort / long window exceeds the configured `diskBudgetGB`, nothing stops or warns at execution time. The app downloads the entire set into memory, causing severe memory pressure and long unresponsive stalls instead of honoring the advertised bound.

**Fix direction:** Gate `executeRun` on `pullEstimate.exceedsDiskBudget` — block or require explicit confirmation before pulling.

---

## 4. Keychain token stored without device-only accessibility — CONFIRMED — Critical (security)
**File:** `Sources/GSMToolsCore/Services/KeychainStore.swift:61` (used by `saveToken` :18, `updateToken` :54)

`baseQuery()` returns only `[kSecClass: kSecClassGenericPassword, kSecAttrService, kSecAttrAccount]` — **no `kSecAttrAccessible`** (e.g. `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) and **no `kSecUseDataProtectionKeychain`**. The CTT personal access token lands in the default file-based keychain with default accessibility.

**Failure:** The token can be carried into backups / migrated to other machines, widening exposure of a credential that grants API access to the organization's entire device fleet.

**Fix direction:** Add `kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and `kSecUseDataProtectionKeychain: true` to the add/update queries.

---

## 5. One missing optional sub-field fails the entire device decode — CONFIRMED — High
**File:** `Sources/GSMToolsCore/Models/APIModels.swift:329` (also `:330 alias`, `:253 fw`)

`DeviceProjectInfoEntry.projectName` and `.alias` use non-optional `container.decode(String.self, …)`; `Device.fw` (`:253`) is likewise non-optional. A missing/null field in **any** nested `projectInfo` entry fails the whole `Device` decode with `keyNotFound`/`valueNotFound`.

**Failure:** When `client.device(imei:)` (called from `AppModel.swift:1171` for the device drilldown) fetches a device whose `projectInfo` contains an entry lacking `alias`/`projectName` (or omitting `fw`), `JSONDecoder.api.decode(Device.self)` throws and the entire drilldown fails with a raw decode error — even though only one optional-in-practice sub-field was absent.

**Fix direction:** Use `decodeIfPresent` (optional) for these fields.

---

## 6. Empty deployment-window array not caught by the `?? fallback` — CONFIRMED — High
**File:** `Sources/GSMTools/App/AppModel.swift:1285` (compare to sibling `:1543`)

`run.analysisMode?.windows(for: …) ?? [fallback]` substitutes the fallback only when the optional chain is `nil`, **not** when `windows(for:)` returns a non-nil **empty** array. For `.sinceDeviceDeployments` / `.compareDeviceDeploymentWindows`, a device with no resolvable deployment timestamp returns `[]` (`RunModels.swift:281–283, 293–295`). The sibling consumer `makeReportMetricWindows` (`:1543`) explicitly guards `.isEmpty`; this one does not.

**Failure:** `makeDeviceSummaries` stores an empty `windows` array for that device, so the Devices/Lifeline drilldown shows blank window metrics and `makeDevicePerformanceFlags` emits no flags — while the generated Report (which guards the empty case and falls back to the full pull range) still counts that device's telemetry. The device is silently blank in one screen but present in the report, with no warning.

**Fix direction:** Guard `.isEmpty` the same way `:1543` does, falling back to the period window.

---

## 7. Battery trend uses only first & last sample — CONFIRMED — Medium
**File:** `Sources/GSMToolsCore/Analysis/MetricCalculator.swift:102` (logic ~99–102)

`batteryTrendVoltsPerDay` is `(last.voltage − first.voltage) / days` using only the two endpoint samples after sorting — not a regression over all points.

**Failure:** A single anomalous voltage reading at the very start or end of the window sets the entire battery trend. A healthy battery can be reported with a steep negative V/day decline (or a declining battery as flat), producing a misleading battery-health figure operators rely on.

**Fix direction:** Compute a least-squares slope over all `(date, voltage)` points.

---

## 8. GPS success rate pinned near 100% — PLAUSIBLE — Medium
**File:** `Sources/GSMToolsCore/Analysis/MetricCalculator.swift:53`

`gpsSuccessRate` denominator is `max(locations.count, Σ gpsAttempts)`. `gpsAttempts` (`APIModels.swift:479`) is `Int?`; when no connection carries it, the sum is 0 so the denominator is `locations.count`, and `successfulFixes` (only GPS-fix rows) ≈ that count.

**Failure:** For a device whose API returns only successful location rows and whose connections lack `gpsAttempts`, the rate computes ≈100% even when most real fix attempts failed. The ≥25% drop detection in `makeDevicePerformanceFlags` never fires, so a device with collapsing GPS yield is reported healthy and no alert is raised.

**Fix direction:** Only compute a rate when a real attempt count is available; otherwise mark it indeterminate rather than ~1.0.

---

## 9. Connection failure rate ignores modem-level failures — PLAUSIBLE — Medium
**File:** `Sources/GSMToolsCore/Analysis/MetricCalculator.swift:68` (chain ~68–73)

The `??` chain is `server["failed"] ?? server["success"].map{!$0} ?? modem["failed"] ?? modem["success"].map{!$0}`. When `server["success"]==true`, the second clause yields a non-nil `Optional(false)`, so `??` short-circuits before the modem clauses are ever evaluated.

**Failure:** A connection that succeeded at the server but failed at the modem (`modem.failed=true`) is counted as a success. Modem-level failures are silently excluded, so `connectionFailureRate` is understated and connection-degradation flags fail to fire.

**Fix direction:** Treat the record as failed if either server **or** modem reports failure, rather than first-non-nil-wins.

---

## 10. Nesting detector double-counts the boundary sample — CONFIRMED — Medium
**File:** `Sources/GSMToolsCore/Analysis/NestingDetector.swift:45` (intervals at `:28`, `:45`; filter at `:78`)

The recent interval is `DateInterval(start: recentStart, end: primary.endDate)` and the baseline is `DateInterval(start: primary.startDate, end: recentStart)`. Both are filtered via `interval.contains(timestamp)`, and `Foundation.DateInterval.contains` is **inclusive on both bounds**.

**Failure:** A sensor sample whose timestamp equals `recentStart` is counted in both `averageActivity(recent)` and `averageActivity(baseline)`. Near the boundary this skews the `activityReduction` ratio, which can push `recentActivity <= baselineActivity*0.5` over/under the threshold and emit (or suppress) a false nesting-likelihood alert for a transmitter.

**Fix direction:** Make one side half-open (e.g. exclude `recentStart` from the baseline).

---

## Below-cap cleanup / reuse items (not individually verified to finding-grade; deduped/quality)

- `MetricCalculator.swift:212–240` — `averageSolarMillivolts/Milliamps/TemperatureCelsius/Activity` are copy-paste compactMap/guard-empty/reduce-over-count averages; a `mean` helper exists in `BaselineAnalyzer` (but is `private`, so not directly reusable as-is).
- `LifelineWorkspaceView.swift:1526, 2442` — inline `max(0, min(1, value))` duplicates the file's own `clamped(_:)` helper (`:3607`).
- `LifelineWorkspaceView.swift:3614` — builds a `DateFormatter` inline instead of using `Support/Formatters.swift`.
- `CTTAPIClient.swift:272` — `JSONDecoder.api` returns a plain default `JSONDecoder()`; named accessor implies config that doesn't exist (no-op abstraction).
- `AppModel.swift:1352 / 1631` — `currentAnalysisWindow(from:)` and `currentWindow(from:)` duplicate selector logic + the literal `["primary","recent","period","all"]` id list.
- `AppModel.swift:1248` — `recordRawCacheMetadata` repeats four near-identical `recordRawCacheEntry(...)` blocks differing only in endpoint name / bundle array / 768 vs 1024 byte constant.
- `AppModel.swift:1317, 1321, 1380, 1729, 1733` + `NestingDetector.swift:76` — copy-pasted `filter { guard let ts = x.timestamp … ; return interval.contains(ts) }` closure.
- `AppModel.swift:259, 297` — `lifelineRunOptions`/`latestLifelineRun` are pass-through alias computed properties.
- `APIModels.swift:152` — identical camelCase/snake_case deployment-field decode boilerplate triplicated across three models.
- `AppModel.swift:313` — `hasCredential` hits the Keychain on every access instead of caching presence state.
- `TelemetryPullRunner.swift:60` — endpoint count `4` hardcoded as separate magic numbers in estimate and progress increment.
- `AppModel.swift:430` — status message hardcodes "30-day" while `loadConnectionCountsForSelectedProject(days:)` is parameterized (CONFIRMED but below cap).
- `TelemetryPullRunner.swift:62` — `DevicePullResult.retryCount` always `0`, never updated by `updateDevice` (CONFIRMED but below cap).
- `AppModel.swift:1639` — `formatPercent` re-implements percentage formatting instead of `Formatters.percent` (CONFIRMED but below cap).
- `APIModels.swift:465, 481` — `SensorRecord.timestamp`/`ConnectionRecord.timestamp` re-parse ISO8601 on every access (efficiency).
- `ReportExporter.swift:25` — PDF export renders a single fixed page; content past one page is silently dropped (flagged by altitude finder).
