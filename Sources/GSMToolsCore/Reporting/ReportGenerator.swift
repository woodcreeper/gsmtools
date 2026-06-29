import Foundation

public struct ReportGenerator: Sendable {
    public init() {}

    public func makeReport(title: String, runId: UUID?, metrics: [MetricSnapshot], flags: [AlertFlag]) -> Report {
        let criticalCount = flags.filter { $0.severity == .critical }.count
        let warningCount = flags.filter { $0.severity == .warning }.count
        let summary = "\(metrics.count) metrics reviewed. \(criticalCount) critical and \(warningCount) warning flags."
        return Report(runId: runId, title: title, summary: summary, metrics: metrics, flags: flags)
    }

    public func markdown(for report: Report) -> String {
        var lines: [String] = [
            "# \(report.title)",
            "",
            "Generated: \(TimestampNormalizer.apiString(from: report.generatedAt))",
            "",
            report.summary,
            "",
            "## Metrics",
            "",
            "| Metric | Value | Unit | Window Start | Window End |",
            "|---|---:|---|---|---|"
        ]

        for metric in report.metrics {
            lines.append("| \(metric.metric.rawValue) | \(format(metric.value)) | \(metric.unit) | \(TimestampNormalizer.apiString(from: metric.windowStart)) | \(TimestampNormalizer.apiString(from: metric.windowEnd)) |")
        }

        lines += ["", "## Flags", "", "| Severity | Mode | Metric | Message |", "|---|---|---|---|"]
        for flag in report.flags {
            lines.append("| \(flag.severity.rawValue) | \(flag.mode.rawValue) | \(flag.metric.rawValue) | \(flag.message) |")
        }

        return lines.joined(separator: "\n")
    }

    public func csv(for report: Report) -> String {
        var rows = ["metric,value,unit,window_start,window_end"]
        rows += report.metrics.map { metric in
            [
                metric.metric.rawValue,
                format(metric.value),
                metric.unit,
                TimestampNormalizer.apiString(from: metric.windowStart),
                TimestampNormalizer.apiString(from: metric.windowEnd)
            ]
            .map(csvEscape)
            .joined(separator: ",")
        }
        return rows.joined(separator: "\n")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
