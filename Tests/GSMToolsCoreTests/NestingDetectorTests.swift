import Foundation
import XCTest
@testable import GSMToolsCore

final class NestingDetectorTests: XCTestCase {
    func testFlagsCandidateNestingPatternWhenLocationsClusterAndActivityDrops() throws {
        let update = Date(timeIntervalSince1970: 1_700_000_000)
        let end = update.addingTimeInterval(5 * 86_400)
        let run = AnalysisRun(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Nesting Watch",
            selectedProjectIds: ["project"],
            selectedIMEIs: ["351"],
            startDate: update.addingTimeInterval(-5 * 86_400),
            endDate: end,
            analysisMode: .sinceConfigUpdate(updateDate: update, comparisonMode: .comparablePriorWindow, beforeStart: nil, beforeEnd: nil)
        )

        let recentDates = [
            end.addingTimeInterval(-2 * 86_400),
            end.addingTimeInterval(-1 * 86_400),
            end.addingTimeInterval(-3_600)
        ]
        let locations = recentDates.map {
            location(date: $0, lat: 47.56000, lon: -122.33000)
        }
        let sensors = [
            sensor(date: update.addingTimeInterval(-4 * 86_400), activity: 100),
            sensor(date: update.addingTimeInterval(-2 * 86_400), activity: 110),
            sensor(date: end.addingTimeInterval(-2 * 86_400), activity: 20),
            sensor(date: end.addingTimeInterval(-1 * 86_400), activity: 25)
        ]
        let bundle = TelemetryBundle(imei: "351", locations: locations, sensors: sensors)

        let flag = try XCTUnwrap(NestingDetector().detect(bundle: bundle, run: run))

        XCTAssertEqual(flag.imei, "351")
        XCTAssertEqual(flag.metric, .nestingLikelihood)
        XCTAssertTrue(flag.message.contains("Candidate nesting-pattern screen"))
    }

    func testBaselineExcludesRecentBoundarySample() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(5 * 86_400)
        let recentStart = end.addingTimeInterval(-3 * 86_400)
        let run = AnalysisRun(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Nesting Watch",
            selectedProjectIds: ["project"],
            selectedIMEIs: ["351"],
            startDate: start,
            endDate: end
        )

        let locations = [
            location(date: recentStart.addingTimeInterval(3_600), lat: 47.56000, lon: -122.33000),
            location(date: recentStart.addingTimeInterval(24 * 3_600), lat: 47.56001, lon: -122.33001),
            location(date: end.addingTimeInterval(-3_600), lat: 47.56002, lon: -122.33002)
        ]
        let sensors = [
            sensor(date: start.addingTimeInterval(6 * 3_600), activity: 100),
            sensor(date: recentStart, activity: 40),
            sensor(date: recentStart.addingTimeInterval(24 * 3_600), activity: 40)
        ]
        let bundle = TelemetryBundle(imei: "351", locations: locations, sensors: sensors)

        let flag = try XCTUnwrap(NestingDetector().detect(bundle: bundle, run: run))

        XCTAssertEqual(flag.metric, .nestingLikelihood)
    }

    private func location(date: Date, lat: Double, lon: Double) -> LocationRecord {
        LocationRecord(
            fixAt: Int64(date.timeIntervalSince1970 * 1_000),
            type: .gps,
            lat: lat,
            lon: lon,
            altM: nil,
            groundSpeedKnts: nil,
            cog: nil,
            hdop: nil,
            pdop: nil,
            vdop: nil,
            satCount: nil,
            timeToFix: nil,
            navMode: nil,
            errorFlag: nil,
            reason: nil,
            uncertaintyM: nil
        )
    }

    private func sensor(date: Date, activity: Int) -> SensorRecord {
        SensorRecord(
            imei: "351",
            time: TimestampNormalizer.apiString(from: date),
            source: .sensor,
            reason: nil,
            battery_v: nil,
            solarMv: nil,
            solarMa: nil,
            tempC: nil,
            activity: activity,
            actCumulative: nil,
            actX: nil,
            actY: nil,
            actZ: nil,
            polarAct: nil
        )
    }
}
