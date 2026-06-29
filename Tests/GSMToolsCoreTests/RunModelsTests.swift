import Foundation
import XCTest
@testable import GSMToolsCore

final class RunModelsTests: XCTestCase {
    func testAllDataWindowUsesObservedBoundsWhenRecordsExist() {
        let requested = AnalysisStudyMode.allData.windows(now: Date(timeIntervalSince1970: 2_000_000_000))[0]
        let observedStart = Date(timeIntervalSince1970: 1_800_000_000)
        let observedEnd = Date(timeIntervalSince1970: 1_800_086_400)

        let resolved = requested.replacingSyntheticAllDataBounds(with: [observedEnd, observedStart])

        XCTAssertEqual(resolved.id, "all")
        XCTAssertEqual(resolved.title, "Observed data")
        XCTAssertEqual(resolved.startDate, observedStart)
        XCTAssertEqual(resolved.endDate, observedEnd.addingTimeInterval(1))
    }

    func testSpecificPeriodKeepsRequestedBounds() {
        let requestedStart = Date(timeIntervalSince1970: 1_000)
        let requestedEnd = Date(timeIntervalSince1970: 2_000)
        let requested = AnalysisWindow(id: "period", title: "Selected period", startDate: requestedStart, endDate: requestedEnd)

        let resolved = requested.replacingSyntheticAllDataBounds(with: [
            Date(timeIntervalSince1970: 1_200),
            Date(timeIntervalSince1970: 1_800)
        ])

        XCTAssertEqual(resolved, requested)
    }
}
