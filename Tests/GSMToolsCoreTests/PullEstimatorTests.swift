import XCTest
@testable import GSMToolsCore

final class PullEstimatorTests: XCTestCase {
    func testEstimateUsesGlobalRateLimit() {
        let estimate = PullEstimator(requestsPerMinute: 60).estimate(
            deviceCount: 200,
            endpointCount: 3,
            estimatedPagesPerEndpoint: 1,
            estimatedRecordsPerPage: 100,
            diskBudgetBytes: 10_000_000_000,
            retentionMode: .fullTelemetry
        )

        XCTAssertEqual(estimate.estimatedRequests, 600)
        XCTAssertEqual(estimate.estimatedMinimumDuration, 600, accuracy: 0.001)
    }

    func testFullTelemetryCanExceedDiskBudget() {
        let estimate = PullEstimator(bytesPerRecordEstimate: 1_000).estimate(
            deviceCount: 10,
            endpointCount: 4,
            estimatedPagesPerEndpoint: 5,
            estimatedRecordsPerPage: 100,
            diskBudgetBytes: 1_000,
            retentionMode: .fullTelemetry
        )

        XCTAssertTrue(estimate.exceedsDiskBudget)
    }
}
