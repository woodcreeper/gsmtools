import Foundation

public struct NestingDetector: Sendable {
    public var minimumLocationCount: Int
    public var maximumClusterRadiusMeters: Double
    public var recentDays: Int
    public var activityReductionRatio: Double

    public init(
        minimumLocationCount: Int = 3,
        maximumClusterRadiusMeters: Double = 150,
        recentDays: Int = 3,
        activityReductionRatio: Double = 0.50
    ) {
        self.minimumLocationCount = minimumLocationCount
        self.maximumClusterRadiusMeters = maximumClusterRadiusMeters
        self.recentDays = recentDays
        self.activityReductionRatio = activityReductionRatio
    }

    public func detect(bundle: TelemetryBundle, run: AnalysisRun) -> AlertFlag? {
        let windows = run.analysisMode?.windows(for: bundle.imei, now: run.endDate) ?? [
            AnalysisWindow(id: "period", title: "Selected period", startDate: run.startDate, endDate: run.endDate)
        ]
        guard let primary = windows.first else { return nil }

        let recentStart = max(primary.startDate, primary.endDate.addingTimeInterval(TimeInterval(-max(1, recentDays)) * 86_400))
        let recentInterval = DateInterval(start: recentStart, end: primary.endDate)
        let recentLocations = bundle.locations.filter { location in
            location.hasUsablePosition && recentInterval.contains(location.timestamp)
        }
        guard recentLocations.count >= minimumLocationCount else { return nil }

        guard let radius = clusterRadiusMeters(locations: recentLocations), radius <= maximumClusterRadiusMeters else {
            return nil
        }

        let calculator = MetricCalculator()
        let recentActivity = calculator.averageActivity(sensors: sensors(bundle.sensors, in: recentInterval))

        let baselineInterval: DateInterval?
        if windows.count > 1 {
            baselineInterval = windows[1].interval
        } else if primary.startDate < recentStart {
            baselineInterval = DateInterval(start: primary.startDate, end: recentStart)
        } else {
            baselineInterval = nil
        }

        guard
            let baselineInterval,
            let recentActivity,
            let baselineActivity = calculator.averageActivity(sensors: sensors(bundle.sensors, in: baselineInterval, includeEnd: false)),
            baselineActivity > 0,
            recentActivity <= baselineActivity * activityReductionRatio
        else {
            return nil
        }

        let reduction = 1 - (recentActivity / baselineActivity)
        return AlertFlag(
            runId: run.id,
            imei: bundle.imei,
            metric: .nestingLikelihood,
            severity: .warning,
            mode: .threshold,
            message: String(
                format: "Candidate nesting-pattern screen: recent fixes stayed within %.0f m and activity is %.0f%% below baseline; review before classifying.",
                radius,
                reduction * 100
            )
        )
    }

    private func sensors(_ sensors: [SensorRecord], in interval: DateInterval, includeEnd: Bool = true) -> [SensorRecord] {
        sensors.filter { sample in
            guard let timestamp = sample.timestamp else { return false }
            if includeEnd {
                return interval.contains(timestamp)
            }
            return timestamp >= interval.start && timestamp < interval.end
        }
    }

    private func clusterRadiusMeters(locations: [LocationRecord]) -> Double? {
        let points = locations.compactMap { location -> (Double, Double)? in
            guard let lat = location.lat, let lon = location.lon else { return nil }
            return (lat, lon)
        }
        guard !points.isEmpty else { return nil }

        let centerLat = points.map(\.0).reduce(0, +) / Double(points.count)
        let centerLon = points.map(\.1).reduce(0, +) / Double(points.count)
        return points
            .map { haversineMeters(from: (centerLat, centerLon), to: $0) }
            .max()
    }

    private func haversineMeters(from: (Double, Double), to: (Double, Double)) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let lat1 = from.0 * .pi / 180
        let lat2 = to.0 * .pi / 180
        let deltaLat = (to.0 - from.0) * .pi / 180
        let deltaLon = (to.1 - from.1) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
