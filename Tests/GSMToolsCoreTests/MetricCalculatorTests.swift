import Foundation
import XCTest
@testable import GSMToolsCore

final class MetricCalculatorTests: XCTestCase {
    func testGPSSuccessRateUsesConnectionAttemptsWhenHigher() {
        let locations = [
            location(ms: 1_000, lat: 1, lon: 2),
            location(ms: 2_000, lat: nil, lon: nil)
        ]
        let connections = [
            connection(id: "a", time: "2025-01-01T00:00:00Z", gpsAttempts: 4)
        ]

        XCTAssertEqual(MetricCalculator().gpsSuccessRate(locations: locations, connections: connections), 0.25)
    }

    func testGPSSuccessRateDoesNotCountFallbackLocationAsGPSFix() {
        let locations = [
            location(ms: 1_000, type: .gps, lat: 1, lon: 2, timeToFix: 20),
            location(ms: 2_000, type: .cellLocate, lat: 1, lon: 2, timeToFix: 4)
        ]

        let calculator = MetricCalculator()

        XCTAssertEqual(calculator.gpsFixCount(locations: locations), 1)
        XCTAssertNil(calculator.gpsSuccessRate(locations: locations))
        XCTAssertEqual(calculator.medianTimeToFixSeconds(locations: locations), 20)
    }

    func testGPSRateIsUnknownWithoutConnectionAttempts() {
        let locations = [
            location(ms: 1_000, lat: 1, lon: 2),
            location(ms: 2_000, lat: 1, lon: 2)
        ]

        XCTAssertNil(MetricCalculator().gpsSuccessRate(locations: locations, connections: []))
        XCTAssertNil(MetricCalculator().gpsFailureRate(locations: locations, connections: []))
    }

    func testConnectionFailureRateFlagsEitherServerOrModemFailure() {
        let connections = [
            connection(id: "server-ok-modem-bad", time: "2025-01-01T00:00:00Z", modem: .object(["failed": .bool(true)]), server: .object(["success": .bool(true)])),
            connection(id: "server-ok-modem-ok", time: "2025-01-01T01:00:00Z", modem: .object(["success": .bool(true)]), server: .object(["success": .bool(true)]))
        ]

        XCTAssertEqual(MetricCalculator().connectionFailureRate(connections: connections), 0.5)
    }

    func testResetCountDetectsUptimeDrop() {
        let connections = [
            connection(id: "a", time: "2025-01-01T00:00:00Z", upTime: 100),
            connection(id: "b", time: "2025-01-01T01:00:00Z", upTime: 200),
            connection(id: "c", time: "2025-01-01T02:00:00Z", upTime: 20)
        ]

        XCTAssertEqual(MetricCalculator().resetCount(connections: connections), 1)
    }

    func testBatteryTrend() throws {
        let sensors = [
            SensorRecord(imei: "1", time: "2025-01-01T00:00:00Z", source: .sensor, reason: nil, battery_v: 4.0, solarMv: nil, solarMa: nil, tempC: nil, activity: nil, actCumulative: nil, actX: nil, actY: nil, actZ: nil, polarAct: nil),
            SensorRecord(imei: "1", time: "2025-01-03T00:00:00Z", source: .sensor, reason: nil, battery_v: 3.8, solarMv: nil, solarMa: nil, tempC: nil, activity: nil, actCumulative: nil, actX: nil, actY: nil, actZ: nil, polarAct: nil)
        ]

        let trend = try XCTUnwrap(MetricCalculator().batteryTrendVoltsPerDay(sensors: sensors))
        XCTAssertEqual(trend, -0.1, accuracy: 0.001)
    }

    func testBatteryTrendUsesLeastSquaresSlope() throws {
        let sensors = [
            SensorRecord(imei: "1", time: "2025-01-01T00:00:00Z", source: .sensor, reason: nil, battery_v: 4.0, solarMv: nil, solarMa: nil, tempC: nil, activity: nil, actCumulative: nil, actX: nil, actY: nil, actZ: nil, polarAct: nil),
            SensorRecord(imei: "1", time: "2025-01-02T00:00:00Z", source: .sensor, reason: nil, battery_v: 3.5, solarMv: nil, solarMa: nil, tempC: nil, activity: nil, actCumulative: nil, actX: nil, actY: nil, actZ: nil, polarAct: nil),
            SensorRecord(imei: "1", time: "2025-01-03T00:00:00Z", source: .sensor, reason: nil, battery_v: 4.2, solarMv: nil, solarMa: nil, tempC: nil, activity: nil, actCumulative: nil, actX: nil, actY: nil, actZ: nil, polarAct: nil)
        ]

        let trend = try XCTUnwrap(MetricCalculator().batteryTrendVoltsPerDay(sensors: sensors))
        XCTAssertEqual(trend, 0.1, accuracy: 0.001)
    }

    func testBatteryRechargeSummaryCountsRecoveredAndUnrecoveredDrops() throws {
        let base = try XCTUnwrap(TimestampNormalizer.parseISO8601("2025-01-01T00:00:00Z"))
        let points = [
            batteryPoint(hours: 0, voltage: 4.20, base: base),
            batteryPoint(hours: 6, voltage: 4.15, base: base),
            batteryPoint(hours: 12, voltage: 4.18, base: base),
            batteryPoint(hours: 18, voltage: 4.19, base: base),
            batteryPoint(hours: 24, voltage: 4.13, base: base)
        ]

        let summary = MetricCalculator().batteryRechargeSummary(points: points)

        XCTAssertEqual(summary.dischargeEvents, 2)
        XCTAssertEqual(summary.recoveredEvents, 1)
        XCTAssertEqual(summary.unrecoveredEvents, 1)
        XCTAssertEqual(summary.recoveryRatio, 0.5)
        XCTAssertEqual(try XCTUnwrap(summary.medianRecoveryHours), 6, accuracy: 0.001)
        XCTAssertEqual(summary.largestDropVolts ?? 0, 0.06, accuracy: 0.001)
    }

    func testCumulativeActivityUsesCounterMovementWhenExposed() {
        let sensors = [
            activitySensor(time: "2025-01-01T00:00:00Z", cumulative: 100),
            activitySensor(time: "2025-01-01T06:00:00Z", cumulative: 145),
            activitySensor(time: "2025-01-01T12:00:00Z", cumulative: 180)
        ]

        XCTAssertEqual(MetricCalculator().cumulativeActivity(sensors: sensors), 80)
    }

    func testCumulativeActivityFallsBackToObservedActivityLoad() {
        let sensors = [
            activitySensor(time: "2025-01-01T00:00:00Z", activity: 10),
            activitySensor(time: "2025-01-01T06:00:00Z", polarAct: 5),
            activitySensor(time: "2025-01-01T12:00:00Z", x: 1, y: 2, z: 3)
        ]

        XCTAssertEqual(MetricCalculator().cumulativeActivity(sensors: sensors), 21)
    }

    private func location(ms: Int64, type: LocationKind = .gps, lat: Double?, lon: Double?, timeToFix: Int? = nil) -> LocationRecord {
        LocationRecord(fixAt: ms, type: type, lat: lat, lon: lon, altM: nil, groundSpeedKnts: nil, cog: nil, hdop: nil, pdop: nil, vdop: nil, satCount: nil, timeToFix: timeToFix, navMode: nil, errorFlag: nil, reason: nil, uncertaintyM: nil)
    }

    private func connection(
        id: String,
        time: String,
        upTime: Int? = nil,
        gpsAttempts: Int? = nil,
        modem: AnyJSON? = nil,
        server: AnyJSON? = nil
    ) -> ConnectionRecord {
        ConnectionRecord(id: id, imei: "1", connectAt: time, modem: modem, server: server, fw: nil, config: nil, configNum: nil, reason: nil, upTimeSeconds: upTime, gpsAttempts: gpsAttempts)
    }

    private func batteryPoint(hours: Double, voltage: Double, base: Date) -> DeviceBatteryPoint {
        DeviceBatteryPoint(id: Int(hours), timestamp: base.addingTimeInterval(hours * 3_600), voltage: voltage)
    }

    private func activitySensor(
        time: String,
        activity: Int? = nil,
        cumulative: Int? = nil,
        polarAct: Int? = nil,
        x: Int? = nil,
        y: Int? = nil,
        z: Int? = nil
    ) -> SensorRecord {
        SensorRecord(
            imei: "1",
            time: time,
            source: .sensor,
            reason: nil,
            battery_v: nil,
            solarMv: nil,
            solarMa: nil,
            tempC: nil,
            activity: activity,
            actCumulative: cumulative,
            actX: x,
            actY: y,
            actZ: z,
            polarAct: polarAct
        )
    }
}
