import Foundation
import XCTest
@testable import GSMToolsCore

final class ReportGeneratorTests: XCTestCase {
    func testMarkdownContainsMetricsAndFlags() {
        let report = ReportGenerator().makeReport(
            title: "Analysis Summary",
            runId: nil,
            metrics: [
                MetricSnapshot(metric: .gpsSuccessRate, value: 0.8, unit: "ratio", windowStart: Date(timeIntervalSince1970: 0), windowEnd: Date(timeIntervalSince1970: 1))
            ],
            flags: [
                AlertFlag(metric: .gpsSuccessRate, severity: .warning, mode: .threshold, message: "Dropped")
            ]
        )

        let markdown = ReportGenerator().markdown(for: report)
        XCTAssertTrue(markdown.contains("# Analysis Summary"))
        XCTAssertTrue(markdown.contains("gpsSuccessRate"))
        XCTAssertTrue(markdown.contains("Dropped"))
    }

    func testExporterProducesDataForAllFormats() {
        let report = ReportGenerator().makeReport(
            title: "Export",
            runId: nil,
            metrics: [
                MetricSnapshot(metric: .resetCount, value: 1, unit: "count", windowStart: Date(timeIntervalSince1970: 0), windowEnd: Date(timeIntervalSince1970: 1))
            ],
            flags: []
        )
        let exporter = ReportExporter()

        XCTAssertFalse(exporter.markdownData(for: report).isEmpty)
        XCTAssertFalse(exporter.csvData(for: report).isEmpty)
        XCTAssertFalse(exporter.pdfData(for: report).isEmpty)
    }
}
