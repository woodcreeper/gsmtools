import Foundation
import XCTest
@testable import GSMToolsCore

final class TimestampNormalizerTests: XCTestCase {
    func testEpochMillisecondsNormalizeToDate() {
        let date = TimestampNormalizer.date(fromEpochMilliseconds: 1_735_689_600_000)
        XCTAssertEqual(date.timeIntervalSince1970, 1_735_689_600, accuracy: 0.001)
    }

    func testISO8601WithAndWithoutFractionalSeconds() throws {
        let withoutFraction = try TimestampNormalizer.parseISO8601("2025-01-01T00:00:00Z")
        let withFraction = try TimestampNormalizer.parseISO8601("2025-01-01T00:00:00.000Z")
        XCTAssertEqual(withoutFraction.timeIntervalSince1970, withFraction.timeIntervalSince1970, accuracy: 0.001)
    }
}
