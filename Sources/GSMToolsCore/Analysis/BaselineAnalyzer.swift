import Foundation

public struct BaselineAnalyzer: Sendable {
    public var settings: BaselineSettings

    public init(settings: BaselineSettings = .defaults) {
        self.settings = settings
    }

    public func previousEqualWindow(for start: Date, end: Date) -> DateInterval {
        let duration = max(0, end.timeIntervalSince(start))
        return DateInterval(start: start.addingTimeInterval(-duration), end: start)
    }

    public func readiness(priorWindows: [PriorWindowSummary]) -> BaselineReadiness {
        guard !priorWindows.isEmpty else {
            return .insufficientBaseline(reason: "No prior baseline windows are available.")
        }

        let qualifying = priorWindows.filter { $0.dataDensity >= settings.minimumDataDensity }
        if qualifying.count >= settings.minimumPriorWindows {
            return .statistical
        }

        if qualifying.isEmpty {
            return .insufficientBaseline(reason: "Prior windows do not meet the minimum data density.")
        }

        return .thresholdFallback
    }
}

public struct PriorWindowSummary: Equatable, Sendable {
    public var interval: DateInterval
    public var dataDensity: Double

    public init(interval: DateInterval, dataDensity: Double) {
        self.interval = interval
        self.dataDensity = dataDensity
    }
}

public struct FlagEvaluator: Sendable {
    public var baselineAnalyzer: BaselineAnalyzer
    public var defaultThresholdDropFraction: Double

    public init(
        baselineAnalyzer: BaselineAnalyzer = BaselineAnalyzer(),
        defaultThresholdDropFraction: Double = 0.25
    ) {
        self.baselineAnalyzer = baselineAnalyzer
        self.defaultThresholdDropFraction = defaultThresholdDropFraction
    }

    public func evaluateDrop(
        metric: MetricKind,
        current: Double,
        baselineValues: [Double],
        priorWindows: [PriorWindowSummary],
        runId: UUID? = nil,
        imei: String? = nil
    ) -> AlertFlag? {
        switch baselineAnalyzer.readiness(priorWindows: priorWindows) {
        case .insufficientBaseline:
            return AlertFlag(
                runId: runId,
                imei: imei,
                metric: metric,
                severity: .info,
                mode: .insufficientBaseline,
                message: "Not enough baseline data to evaluate \(metric.rawValue)."
            )
        case .thresholdFallback:
            guard let baseline = baselineValues.last, baseline > 0 else { return nil }
            let drop = (baseline - current) / baseline
            guard drop >= defaultThresholdDropFraction else { return nil }
            return AlertFlag(
                runId: runId,
                imei: imei,
                metric: metric,
                severity: .warning,
                mode: .threshold,
                message: "\(metric.rawValue) dropped by \(Int(drop * 100))% versus baseline."
            )
        case .statistical:
            guard let mean = baselineValues.mean, let standardDeviation = baselineValues.standardDeviation, standardDeviation > 0 else {
                return nil
            }
            let zScore = (current - mean) / standardDeviation
            guard zScore <= -2 else { return nil }
            return AlertFlag(
                runId: runId,
                imei: imei,
                metric: metric,
                severity: .critical,
                mode: .statistical,
                message: "\(metric.rawValue) is \(String(format: "%.1f", abs(zScore))) standard deviations below baseline."
            )
        }
    }
}

private extension Array where Element == Double {
    var mean: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }

    var standardDeviation: Double? {
        guard let mean, count > 1 else { return nil }
        let variance = map { pow($0 - mean, 2) }.reduce(0, +) / Double(count - 1)
        return sqrt(variance)
    }
}
