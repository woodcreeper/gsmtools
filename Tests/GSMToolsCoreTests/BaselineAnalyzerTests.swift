import Foundation
import XCTest
@testable import GSMToolsCore

final class BaselineAnalyzerTests: XCTestCase {
    func testPreviousEqualWindow() {
        let start = Date(timeIntervalSince1970: 10_000)
        let end = Date(timeIntervalSince1970: 20_000)
        let interval = BaselineAnalyzer().previousEqualWindow(for: start, end: end)
        XCTAssertEqual(interval.start.timeIntervalSince1970, 0, accuracy: 0.001)
        XCTAssertEqual(interval.end, start)
    }

    func testInsufficientBaselineWhenNoWindows() {
        let readiness = BaselineAnalyzer().readiness(priorWindows: [])
        if case .insufficientBaseline = readiness {
            return
        }
        XCTFail("Expected insufficient baseline")
    }

    func testStatisticalReadinessWhenEnoughDenseWindows() {
        let analyzer = BaselineAnalyzer(settings: BaselineSettings(minimumPriorWindows: 4, minimumDataDensity: 0.6))
        let windows = (0..<4).map { index in
            PriorWindowSummary(
                interval: DateInterval(start: Date(timeIntervalSince1970: Double(index)), duration: 1),
                dataDensity: 0.8
            )
        }
        XCTAssertEqual(analyzer.readiness(priorWindows: windows), .statistical)
    }

    func testDeploymentComparisonUsesBoundedBeforeAndAfterWindows() {
        let deployment = Date(timeIntervalSince1970: 10_000)
        let afterEnd = deployment.addingTimeInterval(30 * 86_400)
        let beforeStart = deployment.addingTimeInterval(-30 * 86_400)
        let mode = AnalysisStudyMode.compareDeploymentWindows(
            deploymentDate: deployment,
            afterStart: deployment,
            afterEnd: afterEnd,
            beforeStart: beforeStart,
            beforeEnd: deployment
        )

        let windows = mode.windows(now: afterEnd.addingTimeInterval(86_400))

        XCTAssertEqual(windows.map(\.title), ["After deployment", "Before deployment"])
        XCTAssertEqual(windows[0].startDate, deployment)
        XCTAssertEqual(windows[0].endDate, afterEnd)
        XCTAssertEqual(windows[1].startDate, beforeStart)
        XCTAssertEqual(windows[1].endDate, deployment)
    }

    func testDeviceDeploymentComparisonUsesEachDevicesOwnDeploymentDate() {
        let firstDeployment = Date(timeIntervalSince1970: 10_000)
        let secondDeployment = firstDeployment.addingTimeInterval(7 * 86_400)
        let mode = AnalysisStudyMode.compareDeviceDeploymentWindows(
            deploymentsByIMEI: [
                "first": firstDeployment,
                "second": secondDeployment
            ],
            days: 3
        )

        let firstWindows = mode.windows(for: "first", now: secondDeployment.addingTimeInterval(10 * 86_400))
        let secondWindows = mode.windows(for: "second", now: secondDeployment.addingTimeInterval(10 * 86_400))

        XCTAssertEqual(firstWindows[0].startDate, firstDeployment)
        XCTAssertEqual(firstWindows[0].endDate, firstDeployment.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(firstWindows[1].startDate, firstDeployment.addingTimeInterval(-3 * 86_400))
        XCTAssertEqual(firstWindows[1].endDate, firstDeployment)
        XCTAssertEqual(secondWindows[0].startDate, secondDeployment)
        XCTAssertEqual(secondWindows[0].endDate, secondDeployment.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(secondWindows[1].startDate, secondDeployment.addingTimeInterval(-3 * 86_400))
        XCTAssertEqual(secondWindows[1].endDate, secondDeployment)
    }
}
