import Foundation

public struct AnalysisRun: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var testGroupId: UUID?
    public var name: String
    public var selectedProjectIds: [String]
    public var selectedIMEIs: [String]
    public var startDate: Date
    public var endDate: Date
    public var analysisMode: AnalysisStudyMode?
    public var baselineMode: BaselineMode
    public var retentionMode: RetentionMode
    public var schedule: RunSchedule
    public var phases: [RunPhase]
    public var notes: String
    public var state: RunState
    public var progress: RunProgress
    public var deviceSummaries: [DeviceAnalysisSummary]?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        testGroupId: UUID? = nil,
        name: String,
        selectedProjectIds: [String],
        selectedIMEIs: [String],
        startDate: Date,
        endDate: Date,
        analysisMode: AnalysisStudyMode? = nil,
        baselineMode: BaselineMode = .previousEqualWindow,
        retentionMode: RetentionMode = .metricsPlusBoundedRawCache,
        schedule: RunSchedule = .manual,
        phases: [RunPhase] = [],
        notes: String = "",
        state: RunState = .pending,
        progress: RunProgress = .empty,
        deviceSummaries: [DeviceAnalysisSummary]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.testGroupId = testGroupId
        self.name = name
        self.selectedProjectIds = selectedProjectIds
        self.selectedIMEIs = selectedIMEIs
        self.startDate = startDate
        self.endDate = endDate
        self.analysisMode = analysisMode
        self.baselineMode = baselineMode
        self.retentionMode = retentionMode
        self.schedule = schedule
        self.phases = phases
        self.notes = notes
        self.state = state
        self.progress = progress
        self.deviceSummaries = deviceSummaries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AnalysisWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date

    public init(id: String, title: String, startDate: Date, endDate: Date) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }

    public var interval: DateInterval {
        DateInterval(start: startDate, end: endDate)
    }

    public func replacingSyntheticAllDataBounds(with observedTimestamps: [Date]) -> AnalysisWindow {
        guard id == "all",
              let observedStart = observedTimestamps.min(),
              let observedEnd = observedTimestamps.max()
        else {
            return self
        }

        let boundedStart = max(startDate, observedStart)
        let boundedEnd = min(endDate, observedEnd.addingTimeInterval(1))
        guard boundedStart < boundedEnd else {
            return self
        }

        return AnalysisWindow(
            id: id,
            title: "Observed data",
            startDate: boundedStart,
            endDate: boundedEnd
        )
    }
}

public enum ConfigComparisonMode: String, Codable, CaseIterable, Sendable {
    case comparablePriorWindow
    case customBeforeWindow

    public var displayName: String {
        switch self {
        case .comparablePriorWindow:
            return "Same-length period before update"
        case .customBeforeWindow:
            return "Custom before period"
        }
    }
}

public enum AnalysisStudyMode: Codable, Equatable, Sendable {
    case allData
    case specificPeriod(start: Date, end: Date)
    case lastDays(Int)
    case comparePeriods(primaryStart: Date, primaryEnd: Date, comparisonStart: Date, comparisonEnd: Date)
    case compareLastDaysToPrior(days: Int)
    case sinceDeployment(deploymentDate: Date)
    case sinceDeviceDeployments(deploymentsByIMEI: [String: Date])
    case comparePrePostDeployment(deploymentDate: Date, comparisonMode: ConfigComparisonMode, beforeStart: Date?, beforeEnd: Date?)
    case compareDeploymentWindows(deploymentDate: Date, afterStart: Date, afterEnd: Date, beforeStart: Date, beforeEnd: Date)
    case compareDeviceDeploymentWindows(deploymentsByIMEI: [String: Date], days: Int)
    case sinceConfigUpdate(updateDate: Date, comparisonMode: ConfigComparisonMode, beforeStart: Date?, beforeEnd: Date?)

    public var displayName: String {
        switch self {
        case .allData:
            return "All available data"
        case .specificPeriod:
            return "Specific period"
        case let .lastDays(days):
            return "Last \(days) days"
        case .comparePeriods:
            return "Compare two periods"
        case let .compareLastDaysToPrior(days):
            return "Last \(days) days vs reference \(days) days"
        case .sinceDeployment:
            return "Since deployment"
        case .sinceDeviceDeployments:
            return "Since deployment"
        case .comparePrePostDeployment:
            return "Pre/post deployment"
        case .compareDeploymentWindows:
            return "Pre/post deployment"
        case .compareDeviceDeploymentWindows:
            return "Pre/post deployment"
        case .sinceConfigUpdate:
            return "Since config update vs before"
        }
    }

    public func windows(now: Date = Date(), calendar: Calendar = .current) -> [AnalysisWindow] {
        switch self {
        case .allData:
            return [
                AnalysisWindow(
                    id: "all",
                    title: "All available data",
                    startDate: Date(timeIntervalSince1970: 946_684_800),
                    endDate: now
                )
            ]
        case let .specificPeriod(start, end):
            return [AnalysisWindow(id: "period", title: "Selected period", startDate: start, endDate: end)]
        case let .lastDays(days):
            let end = now
            let start = calendar.date(byAdding: .day, value: -max(1, days), to: end) ?? end.addingTimeInterval(TimeInterval(-max(1, days)) * 86_400)
            return [AnalysisWindow(id: "recent", title: "Last \(max(1, days)) days", startDate: start, endDate: end)]
        case let .comparePeriods(primaryStart, primaryEnd, comparisonStart, comparisonEnd):
            return [
                AnalysisWindow(id: "primary", title: "Primary period", startDate: primaryStart, endDate: primaryEnd),
                AnalysisWindow(id: "comparison", title: "Comparison period", startDate: comparisonStart, endDate: comparisonEnd)
            ]
        case let .compareLastDaysToPrior(days):
            let boundedDays = max(1, days)
            let primaryEnd = now
            let primaryStart = calendar.date(byAdding: .day, value: -boundedDays, to: primaryEnd) ?? primaryEnd.addingTimeInterval(TimeInterval(-boundedDays) * 86_400)
            let comparisonEnd = primaryStart
            let comparisonStart = calendar.date(byAdding: .day, value: -boundedDays, to: comparisonEnd) ?? comparisonEnd.addingTimeInterval(TimeInterval(-boundedDays) * 86_400)
            return [
                AnalysisWindow(id: "primary", title: "Last \(boundedDays) days", startDate: primaryStart, endDate: primaryEnd),
                AnalysisWindow(id: "comparison", title: "Prior \(boundedDays) days", startDate: comparisonStart, endDate: comparisonEnd)
            ]
        case let .sinceDeployment(deploymentDate):
            return [
                AnalysisWindow(id: "primary", title: "Since deployment", startDate: deploymentDate, endDate: now)
            ]
        case let .sinceDeviceDeployments(deploymentsByIMEI):
            let deployments = deploymentsByIMEI.values.filter { $0 < now }
            guard let start = deployments.min() else {
                return []
            }
            return [
                AnalysisWindow(
                    id: "primary",
                    title: "Since per-device deployment",
                    startDate: start,
                    endDate: now
                )
            ]
        case let .comparePrePostDeployment(deploymentDate, comparisonMode, beforeStart, beforeEnd):
            let primary = AnalysisWindow(id: "primary", title: "After deployment", startDate: deploymentDate, endDate: now)
            let comparison: AnalysisWindow
            switch comparisonMode {
            case .comparablePriorWindow:
                let duration = max(1, now.timeIntervalSince(deploymentDate))
                comparison = AnalysisWindow(
                    id: "comparison",
                    title: "Same length before deployment",
                    startDate: deploymentDate.addingTimeInterval(-duration),
                    endDate: deploymentDate
                )
            case .customBeforeWindow:
                comparison = AnalysisWindow(
                    id: "comparison",
                    title: "Custom before deployment",
                    startDate: beforeStart ?? deploymentDate.addingTimeInterval(-7 * 86_400),
                    endDate: beforeEnd ?? deploymentDate
                )
            }
            return [primary, comparison]
        case let .compareDeploymentWindows(_, afterStart, afterEnd, beforeStart, beforeEnd):
            return [
                AnalysisWindow(id: "primary", title: "After deployment", startDate: afterStart, endDate: afterEnd),
                AnalysisWindow(id: "comparison", title: "Before deployment", startDate: beforeStart, endDate: beforeEnd)
            ]
        case let .compareDeviceDeploymentWindows(deploymentsByIMEI, days):
            let deviceWindows = deploymentsByIMEI.values
                .filter { $0 < now }
                .map { Self.deviceDeploymentWindows(deploymentDate: $0, days: days, now: now) }
            guard let first = deviceWindows.first else {
                return []
            }
            return [
                AnalysisWindow(
                    id: "primary",
                    title: "After per-device deployment",
                    startDate: deviceWindows.map(\.primary.startDate).min() ?? first.primary.startDate,
                    endDate: deviceWindows.map(\.primary.endDate).max() ?? first.primary.endDate
                ),
                AnalysisWindow(
                    id: "comparison",
                    title: "Before per-device deployment",
                    startDate: deviceWindows.map(\.comparison.startDate).min() ?? first.comparison.startDate,
                    endDate: deviceWindows.map(\.comparison.endDate).max() ?? first.comparison.endDate
                )
            ]
        case let .sinceConfigUpdate(updateDate, comparisonMode, beforeStart, beforeEnd):
            let primary = AnalysisWindow(id: "primary", title: "After config update", startDate: updateDate, endDate: now)
            let comparison: AnalysisWindow
            switch comparisonMode {
            case .comparablePriorWindow:
                let duration = max(1, now.timeIntervalSince(updateDate))
                comparison = AnalysisWindow(
                    id: "comparison",
                    title: "Same length before update",
                    startDate: updateDate.addingTimeInterval(-duration),
                    endDate: updateDate
                )
            case .customBeforeWindow:
                comparison = AnalysisWindow(
                    id: "comparison",
                    title: "Custom before period",
                    startDate: beforeStart ?? updateDate.addingTimeInterval(-7 * 86_400),
                    endDate: beforeEnd ?? updateDate
                )
            }
            return [primary, comparison]
        }
    }

    public func windows(for imei: String, now: Date = Date(), calendar: Calendar = .current) -> [AnalysisWindow] {
        switch self {
        case let .sinceDeviceDeployments(deploymentsByIMEI):
            guard let deploymentDate = deploymentsByIMEI[imei], deploymentDate < now else {
                return []
            }
            return [
                AnalysisWindow(
                    id: "primary",
                    title: "Since deployment",
                    startDate: deploymentDate,
                    endDate: now
                )
            ]
        case let .compareDeviceDeploymentWindows(deploymentsByIMEI, days):
            guard let deploymentDate = deploymentsByIMEI[imei], deploymentDate < now else {
                return []
            }
            let windows = Self.deviceDeploymentWindows(deploymentDate: deploymentDate, days: days, now: now)
            return [windows.primary, windows.comparison]
        default:
            return windows(now: now, calendar: calendar)
        }
    }

    public func pullRange(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let windows = windows(now: now, calendar: calendar)
        guard let first = windows.first else {
            return DateInterval(start: now, end: now)
        }
        let start = windows.map(\.startDate).min() ?? first.startDate
        let end = windows.map(\.endDate).max() ?? first.endDate
        return DateInterval(start: start, end: end)
    }

    private static func deviceDeploymentWindows(
        deploymentDate: Date,
        days: Int,
        now: Date
    ) -> (primary: AnalysisWindow, comparison: AnalysisWindow) {
        let duration = TimeInterval(max(1, days) * 86_400)
        let afterEnd = min(now, deploymentDate.addingTimeInterval(duration))
        return (
            primary: AnalysisWindow(
                id: "primary",
                title: "After deployment",
                startDate: deploymentDate,
                endDate: afterEnd
            ),
            comparison: AnalysisWindow(
                id: "comparison",
                title: "Before deployment",
                startDate: deploymentDate.addingTimeInterval(-duration),
                endDate: deploymentDate
            )
        )
    }
}

public struct TestGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var projectIds: [String]
    public var deviceIMEIs: [String]
    public var notes: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        projectIds: [String],
        deviceIMEIs: [String],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.projectIds = projectIds
        self.deviceIMEIs = deviceIMEIs
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum BaselineMode: String, Codable, CaseIterable, Sendable {
    case previousEqualWindow
}

public enum RetentionMode: String, Codable, CaseIterable, Sendable {
    case metricsPlusBoundedRawCache
    case fullTelemetry

    public var displayName: String {
        switch self {
        case .metricsPlusBoundedRawCache:
            return "Metrics + bounded raw cache"
        case .fullTelemetry:
            return "Full telemetry"
        }
    }
}

public enum RunState: String, Codable, CaseIterable, Sendable {
    case pending
    case estimating
    case running
    case succeeded
    case partial
    case failed
    case canceled
}

public struct RunProgress: Codable, Equatable, Sendable {
    public var completedRequests: Int
    public var estimatedRequests: Int
    public var deviceResults: [DevicePullResult]

    public static let empty = RunProgress(completedRequests: 0, estimatedRequests: 0, deviceResults: [])

    public var fractionComplete: Double {
        guard estimatedRequests > 0 else { return 0 }
        return min(1, Double(completedRequests) / Double(estimatedRequests))
    }
}

public struct DevicePullResult: Codable, Equatable, Identifiable, Sendable {
    public var imei: String
    public var state: DevicePullState
    public var retryCount: Int
    public var message: String?

    public var id: String { imei }

    public init(imei: String, state: DevicePullState, retryCount: Int, message: String?) {
        self.imei = imei
        self.state = state
        self.retryCount = retryCount
        self.message = message
    }
}

public enum DevicePullState: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case succeeded
    case skipped
    case failed
}

public struct DeviceAnalysisSummary: Codable, Equatable, Identifiable, Sendable {
    public var imei: String
    public var windows: [DeviceWindowMetrics]
    public var lifelineBuckets: [DeviceLifelineBucket]
    public var fixPoints: [DeviceFixPoint]
    public var batteryPoints: [DeviceBatteryPoint]?
    public var totalLocations: Int
    public var totalSensors: Int
    public var totalConnections: Int
    public var generatedAt: Date

    public var id: String { imei }

    public init(
        imei: String,
        windows: [DeviceWindowMetrics],
        lifelineBuckets: [DeviceLifelineBucket],
        fixPoints: [DeviceFixPoint],
        batteryPoints: [DeviceBatteryPoint]? = nil,
        totalLocations: Int,
        totalSensors: Int,
        totalConnections: Int,
        generatedAt: Date = Date()
    ) {
        self.imei = imei
        self.windows = windows
        self.lifelineBuckets = lifelineBuckets
        self.fixPoints = fixPoints
        self.batteryPoints = batteryPoints
        self.totalLocations = totalLocations
        self.totalSensors = totalSensors
        self.totalConnections = totalConnections
        self.generatedAt = generatedAt
    }
}

public struct DeviceWindowMetrics: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var gpsFixCount: Int
    public var fallbackFixCount: Int
    public var gpsSuccessRate: Double?
    public var gpsFailureRate: Double?
    public var gpsFixCadenceHours: Double?
    public var medianTimeToFixSeconds: Double?
    public var connectionCount: Int
    public var connectionFailureRate: Double?
    public var checkInCadenceHours: Double?
    public var batteryTrendVoltsPerDay: Double?
    public var medianBatteryVoltage: Double?
    public var solarMillivolts: Double?
    public var solarMilliamps: Double?
    public var solarExposureRate: Double?
    public var temperatureCelsius: Double?
    public var activityMean: Double?
    public var activityCumulative: Double?
    public var resetCount: Int

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        gpsFixCount: Int,
        fallbackFixCount: Int,
        gpsSuccessRate: Double?,
        gpsFailureRate: Double?,
        gpsFixCadenceHours: Double?,
        medianTimeToFixSeconds: Double?,
        connectionCount: Int,
        connectionFailureRate: Double?,
        checkInCadenceHours: Double?,
        batteryTrendVoltsPerDay: Double?,
        medianBatteryVoltage: Double?,
        solarMillivolts: Double?,
        solarMilliamps: Double?,
        solarExposureRate: Double?,
        temperatureCelsius: Double?,
        activityMean: Double?,
        activityCumulative: Double?,
        resetCount: Int
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.gpsFixCount = gpsFixCount
        self.fallbackFixCount = fallbackFixCount
        self.gpsSuccessRate = gpsSuccessRate
        self.gpsFailureRate = gpsFailureRate
        self.gpsFixCadenceHours = gpsFixCadenceHours
        self.medianTimeToFixSeconds = medianTimeToFixSeconds
        self.connectionCount = connectionCount
        self.connectionFailureRate = connectionFailureRate
        self.checkInCadenceHours = checkInCadenceHours
        self.batteryTrendVoltsPerDay = batteryTrendVoltsPerDay
        self.medianBatteryVoltage = medianBatteryVoltage
        self.solarMillivolts = solarMillivolts
        self.solarMilliamps = solarMilliamps
        self.solarExposureRate = solarExposureRate
        self.temperatureCelsius = temperatureCelsius
        self.activityMean = activityMean
        self.activityCumulative = activityCumulative
        self.resetCount = resetCount
    }
}

public struct DeviceLifelineBucket: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var startDate: Date
    public var endDate: Date
    public var gpsFixCount: Int
    public var fallbackFixCount: Int
    public var connectionCount: Int

    public init(
        id: Int,
        startDate: Date,
        endDate: Date,
        gpsFixCount: Int,
        fallbackFixCount: Int,
        connectionCount: Int
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.gpsFixCount = gpsFixCount
        self.fallbackFixCount = fallbackFixCount
        self.connectionCount = connectionCount
    }
}

public struct DeviceFixPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var timestamp: Date
    public var lat: Double
    public var lon: Double
    public var isFallback: Bool
    public var type: LocationKind?
    public var timeToFix: Int?
    public var hdop: Double?
    public var satCount: Int?
    public var uncertaintyM: Double?

    public init(
        id: Int,
        timestamp: Date,
        lat: Double,
        lon: Double,
        isFallback: Bool,
        type: LocationKind? = nil,
        timeToFix: Int? = nil,
        hdop: Double? = nil,
        satCount: Int? = nil,
        uncertaintyM: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.lat = lat
        self.lon = lon
        self.isFallback = isFallback
        self.type = type
        self.timeToFix = timeToFix
        self.hdop = hdop
        self.satCount = satCount
        self.uncertaintyM = uncertaintyM
    }
}

public struct DeviceBatteryPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var timestamp: Date
    public var voltage: Double
    public var solarMillivolts: Int?
    public var solarMilliamps: Int?

    public init(
        id: Int,
        timestamp: Date,
        voltage: Double,
        solarMillivolts: Int? = nil,
        solarMilliamps: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.voltage = voltage
        self.solarMillivolts = solarMillivolts
        self.solarMilliamps = solarMilliamps
    }
}

public struct RunPhase: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var startsAt: Date?
    public var endsAt: Date?
    public var notes: String

    public init(id: UUID = UUID(), title: String, startsAt: Date? = nil, endsAt: Date? = nil, notes: String = "") {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.notes = notes
    }
}

public enum RunSchedule: Codable, Equatable, Sendable {
    case manual
    case daily
    case weekly
    case customInterval(hours: Int)

    public var displayName: String {
        switch self {
        case .manual:
            return "Manual"
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case let .customInterval(hours):
            return "Every \(hours)h"
        }
    }
}

public struct MetricSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var metric: MetricKind
    public var value: Double
    public var unit: String
    public var windowStart: Date
    public var windowEnd: Date

    public init(id: UUID = UUID(), metric: MetricKind, value: Double, unit: String, windowStart: Date, windowEnd: Date) {
        self.id = id
        self.metric = metric
        self.value = value
        self.unit = unit
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }
}

public enum MetricKind: String, Codable, CaseIterable, Sendable {
    case gpsFixCount
    case gpsFixCadenceHours
    case gpsSuccessRate
    case gpsFailureRate
    case medianTimeToFixSeconds
    case connectionCount
    case checkInCadenceHours
    case connectionFailureRate
    case batteryTrendVoltsPerDay
    case medianBatteryVoltage
    case solarMillivolts
    case solarMilliamps
    case solarExposureRate
    case temperatureCelsius
    case activityMean
    case activityCumulative
    case nestingLikelihood
    case resetCount
    case rssi
}

public struct AlertFlag: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var runId: UUID?
    public var imei: String?
    public var metric: MetricKind
    public var severity: AlertSeverity
    public var mode: FlagMode
    public var message: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        runId: UUID? = nil,
        imei: String? = nil,
        metric: MetricKind,
        severity: AlertSeverity,
        mode: FlagMode,
        message: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.runId = runId
        self.imei = imei
        self.metric = metric
        self.severity = severity
        self.mode = mode
        self.message = message
        self.createdAt = createdAt
    }
}

public enum AlertSeverity: String, Codable, CaseIterable, Sendable {
    case info
    case warning
    case critical
}

public enum FlagMode: String, Codable, CaseIterable, Sendable {
    case statistical
    case threshold
    case insufficientBaseline
}

public struct Report: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var runId: UUID?
    public var title: String
    public var generatedAt: Date
    public var summary: String
    public var metrics: [MetricSnapshot]
    public var flags: [AlertFlag]

    public init(
        id: UUID = UUID(),
        runId: UUID? = nil,
        title: String,
        generatedAt: Date = Date(),
        summary: String,
        metrics: [MetricSnapshot],
        flags: [AlertFlag]
    ) {
        self.id = id
        self.runId = runId
        self.title = title
        self.generatedAt = generatedAt
        self.summary = summary
        self.metrics = metrics
        self.flags = flags
    }
}

public struct PullEstimate: Codable, Equatable, Sendable {
    public var deviceCount: Int
    public var endpointCount: Int
    public var estimatedPagesPerEndpoint: Int
    public var estimatedRequests: Int
    public var estimatedMinimumDuration: TimeInterval
    public var estimatedBytes: Int64
    public var exceedsDiskBudget: Bool

    public init(
        deviceCount: Int,
        endpointCount: Int,
        estimatedPagesPerEndpoint: Int,
        estimatedRequests: Int,
        estimatedMinimumDuration: TimeInterval,
        estimatedBytes: Int64,
        exceedsDiskBudget: Bool
    ) {
        self.deviceCount = deviceCount
        self.endpointCount = endpointCount
        self.estimatedPagesPerEndpoint = estimatedPagesPerEndpoint
        self.estimatedRequests = estimatedRequests
        self.estimatedMinimumDuration = estimatedMinimumDuration
        self.estimatedBytes = estimatedBytes
        self.exceedsDiskBudget = exceedsDiskBudget
    }
}

public struct BaselineSettings: Codable, Equatable, Sendable {
    public var minimumPriorWindows: Int
    public var minimumDataDensity: Double

    public static let defaults = BaselineSettings(minimumPriorWindows: 4, minimumDataDensity: 0.60)
}

public enum BaselineReadiness: Equatable, Sendable {
    case statistical
    case thresholdFallback
    case insufficientBaseline(reason: String)
}
