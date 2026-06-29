import Foundation
import XCTest
@testable import GSMToolsCore

final class TelemetryPullRunnerTests: XCTestCase {
    func testPartialRunWhenOneDeviceFails() async {
        let run = AnalysisRun(
            name: "Partial",
            selectedProjectIds: ["project"],
            selectedIMEIs: ["ok", "bad"],
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1)
        )
        let runner = TelemetryPullRunner(client: FakeTelemetryClient(failingIMEIs: ["bad"]))

        let outcome = await runner.run(run)

        XCTAssertEqual(outcome.run.state, .partial)
        XCTAssertEqual(outcome.bundles.map(\.imei), ["ok"])
        XCTAssertEqual(outcome.run.progress.deviceResults.first(where: { $0.imei == "ok" })?.state, .succeeded)
        XCTAssertEqual(outcome.run.progress.deviceResults.first(where: { $0.imei == "bad" })?.state, .failed)
    }
}

private struct FakeTelemetryClient: TelemetryPulling {
    var failingIMEIs: Set<String>

    func allLocations(imei: String, start: Date, end: Date, limit: Int) async throws -> [LocationRecord] {
        try maybeFail(imei)
        return []
    }

    func allSensors(imei: String, start: Date, end: Date, limit: Int) async throws -> [SensorRecord] {
        try maybeFail(imei)
        return []
    }

    func allConnections(imei: String, start: Date, end: Date, limit: Int) async throws -> [ConnectionRecord] {
        try maybeFail(imei)
        return []
    }

    func allInstructions(imei: String, filter: InstructionsFilter, limit: Int) async throws -> [Instruction] {
        try maybeFail(imei)
        return []
    }

    private func maybeFail(_ imei: String) throws {
        if failingIMEIs.contains(imei) {
            throw CTTAPIError(statusCode: 503, code: .serviceUnavailable, message: "Unavailable", requestId: "test")
        }
    }
}
