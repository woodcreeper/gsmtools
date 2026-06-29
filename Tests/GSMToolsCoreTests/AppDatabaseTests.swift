import Foundation
import XCTest
@testable import GSMToolsCore

final class AppDatabaseTests: XCTestCase {
    func testRunRoundTrip() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
        let database = try AppDatabase(path: path)
        let groupId = UUID()
        let created = Date(timeIntervalSince1970: 100)
        let updated = Date(timeIntervalSince1970: 200)
        let run = AnalysisRun(
            testGroupId: groupId,
            name: "Test",
            selectedProjectIds: ["project"],
            selectedIMEIs: ["12345678901234"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1),
            createdAt: created,
            updatedAt: updated
        )

        try database.saveRun(run)
        let runs = try database.fetchRuns()

        XCTAssertEqual(runs, [run])
    }

    func testRunRoundTripWithDeviceSummaries() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
        let database = try AppDatabase(path: path)
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let summary = DeviceAnalysisSummary(
            imei: "12345678901234",
            windows: [
                DeviceWindowMetrics(
                    id: "primary",
                    title: "Last 30 days",
                    startDate: start,
                    endDate: end,
                    gpsFixCount: 42,
                    fallbackFixCount: 3,
                    gpsSuccessRate: 0.82,
                    gpsFailureRate: 0.18,
                    gpsFixCadenceHours: 2.4,
                    medianTimeToFixSeconds: 38,
                    connectionCount: 50,
                    connectionFailureRate: nil,
                    checkInCadenceHours: 1.9,
                    batteryTrendVoltsPerDay: -0.01,
                    medianBatteryVoltage: 3.91,
                    solarMillivolts: 640,
                    solarMilliamps: 12,
                    solarExposureRate: 0.62,
                    temperatureCelsius: 18.5,
                    activityMean: 22,
                    activityCumulative: 450,
                    resetCount: 1
                )
            ],
            lifelineBuckets: [
                DeviceLifelineBucket(id: 0, startDate: start, endDate: end, gpsFixCount: 2, fallbackFixCount: 0, connectionCount: 3)
            ],
            fixPoints: [
                DeviceFixPoint(id: 0, timestamp: start, lat: 47.1, lon: -122.2, isFallback: false)
            ],
            totalLocations: 45,
            totalSensors: 12,
            totalConnections: 50,
            generatedAt: end
        )
        let run = AnalysisRun(
            name: "With summaries",
            selectedProjectIds: ["project"],
            selectedIMEIs: [summary.imei],
            startDate: start,
            endDate: end,
            state: .succeeded,
            deviceSummaries: [summary],
            createdAt: start,
            updatedAt: end
        )

        try database.saveRun(run)

        XCTAssertEqual(try database.fetchRuns(), [run])
    }

    func testTestGroupRoundTrip() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
        let database = try AppDatabase(path: path)
        let group = TestGroup(
            name: "Aggressive GPS test",
            projectIds: ["project"],
            deviceIMEIs: ["12345678901234", "12345678901235"],
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        try database.saveTestGroup(group)
        let groups = try database.fetchTestGroups()

        XCTAssertEqual(groups, [group])
    }

    func testDeleteRunRemovesAssociatedLocalData() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
        let database = try AppDatabase(path: path)
        let run = AnalysisRun(
            name: "Delete Me",
            selectedProjectIds: ["project"],
            selectedIMEIs: ["12345678901234"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1)
        )
        let report = Report(
            runId: run.id,
            title: "Run Report",
            summary: "Summary",
            metrics: [],
            flags: []
        )
        let flag = AlertFlag(
            runId: run.id,
            metric: .gpsSuccessRate,
            severity: .warning,
            mode: .threshold,
            message: "Dropped"
        )

        try database.saveRun(run)
        try database.saveReport(report)
        try database.saveAlert(flag)
        try database.recordRawCacheEntry(runId: run.id, imei: "12345678901234", endpoint: "locations", recordCount: 1, byteCount: 128)

        try database.deleteRun(id: run.id)

        XCTAssertEqual(try database.fetchRuns(), [])
        XCTAssertEqual(try database.fetchReports(), [])
        XCTAssertEqual(try database.fetchAlerts(), [])
        XCTAssertEqual(try database.rawCacheBytes(), 0)
    }

    func testRawTelemetryRoundTripAndDelete() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
        let database = try AppDatabase(path: path)
        let run = AnalysisRun(
            name: "Full Retention",
            selectedProjectIds: ["project"],
            selectedIMEIs: ["12345678901234"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1),
            retentionMode: .fullTelemetry
        )
        let bundle = TelemetryBundle(
            imei: "12345678901234",
            locations: [location(ms: 1_000)],
            sensors: [],
            connections: [],
            instructions: []
        )

        try database.saveRun(run)
        try database.saveRawTelemetry(runId: run.id, bundles: [bundle])
        let entries = try database.fetchRawTelemetryEntries(runId: run.id)

        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries.first(where: { $0.endpoint == "locations" })?.recordCount, 1)
        XCTAssertFalse(entries.first(where: { $0.endpoint == "locations" })?.payload.isEmpty ?? true)

        try database.deleteRun(id: run.id)

        XCTAssertEqual(try database.fetchRawTelemetryEntries(runId: run.id), [])
    }

    private func location(ms: Int64) -> LocationRecord {
        LocationRecord(fixAt: ms, type: .gps, lat: 47.0, lon: -122.0, altM: nil, groundSpeedKnts: nil, cog: nil, hdop: nil, pdop: nil, vdop: nil, satCount: nil, timeToFix: nil, navMode: nil, errorFlag: nil, reason: nil, uncertaintyM: nil)
    }
}
