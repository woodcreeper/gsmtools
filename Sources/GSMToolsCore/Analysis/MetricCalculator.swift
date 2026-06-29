import Foundation

public struct BatteryRechargeSummary: Equatable, Sendable {
    public var sampleCount: Int
    public var dischargeEvents: Int
    public var recoveredEvents: Int
    public var unrecoveredEvents: Int
    public var recoveryRatio: Double?
    public var medianRecoveryHours: Double?
    public var largestDropVolts: Double?
    public var startVoltage: Double?
    public var endVoltage: Double?
    public var startDate: Date?
    public var endDate: Date?

    public init(
        sampleCount: Int,
        dischargeEvents: Int,
        recoveredEvents: Int,
        unrecoveredEvents: Int,
        recoveryRatio: Double?,
        medianRecoveryHours: Double?,
        largestDropVolts: Double?,
        startVoltage: Double?,
        endVoltage: Double?,
        startDate: Date?,
        endDate: Date?
    ) {
        self.sampleCount = sampleCount
        self.dischargeEvents = dischargeEvents
        self.recoveredEvents = recoveredEvents
        self.unrecoveredEvents = unrecoveredEvents
        self.recoveryRatio = recoveryRatio
        self.medianRecoveryHours = medianRecoveryHours
        self.largestDropVolts = largestDropVolts
        self.startVoltage = startVoltage
        self.endVoltage = endVoltage
        self.startDate = startDate
        self.endDate = endDate
    }
}

public struct MetricCalculator: Sendable {
    public init() {}

    public func gpsFixCount(locations: [LocationRecord]) -> Int {
        locations.filter(isGPSFix).count
    }

    public func gpsSuccessRate(locations: [LocationRecord], connections: [ConnectionRecord] = []) -> Double? {
        let successfulFixes = gpsFixCount(locations: locations)
        let attemptsFromConnections = connections.compactMap(\.gpsAttempts).reduce(0, +)

        guard attemptsFromConnections > 0 else { return nil }
        let attempts = max(successfulFixes, attemptsFromConnections)
        return Double(successfulFixes) / Double(attempts)
    }

    public func gpsFailureRate(locations: [LocationRecord], connections: [ConnectionRecord] = []) -> Double? {
        gpsSuccessRate(locations: locations, connections: connections).map { max(0, 1 - $0) }
    }

    public func connectionCount(connections: [ConnectionRecord]) -> Int {
        connections.count
    }

    public func connectionFailureRate(connections: [ConnectionRecord]) -> Double? {
        let outcomes = connections.compactMap(connectionFailed)
        guard !outcomes.isEmpty else { return nil }
        return Double(outcomes.filter { $0 }.count) / Double(outcomes.count)
    }

    public func medianTimeBetweenFixesHours(locations: [LocationRecord]) -> Double? {
        let sortedDates = locations.filter(isGPSFix).map(\.timestamp).sorted()
        return medianIntervalHours(sortedDates)
    }

    public func medianCheckInCadenceHours(connections: [ConnectionRecord]) -> Double? {
        let sortedDates = connections.compactMap(\.timestamp).sorted()
        return medianIntervalHours(sortedDates)
    }

    public func medianTimeToFixSeconds(locations: [LocationRecord]) -> Double? {
        median(locations.filter(isGPSFix).compactMap { $0.timeToFix.map(Double.init) })
    }

    public func batteryTrendVoltsPerDay(sensors: [SensorRecord]) -> Double? {
        let points = sensors.compactMap { sample -> (Date, Double)? in
            guard let date = sample.timestamp, let voltage = sample.battery_v else { return nil }
            return (date, voltage)
        }
        .sorted { $0.0 < $1.0 }

        guard let origin = points.first?.0, points.count > 1 else { return nil }
        let regressionPoints = points.map { point in
            (x: point.0.timeIntervalSince(origin) / 86_400, y: point.1)
        }
        let meanX = regressionPoints.map(\.x).reduce(0, +) / Double(regressionPoints.count)
        let meanY = regressionPoints.map(\.y).reduce(0, +) / Double(regressionPoints.count)
        let denominator = regressionPoints.reduce(0) { partial, point in
            partial + pow(point.x - meanX, 2)
        }
        guard denominator > 0 else { return nil }
        let numerator = regressionPoints.reduce(0) { partial, point in
            partial + (point.x - meanX) * (point.y - meanY)
        }
        return numerator / denominator
    }

    public func medianBatteryVoltage(sensors: [SensorRecord]) -> Double? {
        median(sensors.compactMap(\.battery_v))
    }

    public func batteryRechargeSummary(
        points: [DeviceBatteryPoint],
        dischargeThresholdVolts: Double = 0.03,
        recoveryThresholdVolts: Double = 0.02
    ) -> BatteryRechargeSummary {
        let sorted = points
            .filter { $0.voltage.isFinite }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = sorted.first else {
            return BatteryRechargeSummary(
                sampleCount: 0,
                dischargeEvents: 0,
                recoveredEvents: 0,
                unrecoveredEvents: 0,
                recoveryRatio: nil,
                medianRecoveryHours: nil,
                largestDropVolts: nil,
                startVoltage: nil,
                endVoltage: nil,
                startDate: nil,
                endDate: nil
            )
        }

        var peakVoltage = first.voltage
        var lowVoltage = first.voltage
        var lowDate = first.timestamp
        var inDischarge = false
        var recoveredEvents = 0
        var unrecoveredEvents = 0
        var largestDrop = 0.0
        var recoveryHours: [Double] = []

        for point in sorted.dropFirst() {
            if !inDischarge {
                if point.voltage >= peakVoltage {
                    peakVoltage = point.voltage
                    continue
                }

                let drop = peakVoltage - point.voltage
                if drop >= dischargeThresholdVolts {
                    inDischarge = true
                    lowVoltage = point.voltage
                    lowDate = point.timestamp
                    largestDrop = max(largestDrop, drop)
                }
                continue
            }

            if point.voltage < lowVoltage {
                lowVoltage = point.voltage
                lowDate = point.timestamp
                largestDrop = max(largestDrop, peakVoltage - point.voltage)
                continue
            }

            if point.voltage - lowVoltage >= recoveryThresholdVolts {
                recoveredEvents += 1
                recoveryHours.append(point.timestamp.timeIntervalSince(lowDate) / 3_600)
                inDischarge = false
                peakVoltage = point.voltage
            }
        }

        if inDischarge {
            unrecoveredEvents += 1
        }

        let dischargeEvents = recoveredEvents + unrecoveredEvents
        let last = sorted[sorted.count - 1]

        return BatteryRechargeSummary(
            sampleCount: sorted.count,
            dischargeEvents: dischargeEvents,
            recoveredEvents: recoveredEvents,
            unrecoveredEvents: unrecoveredEvents,
            recoveryRatio: dischargeEvents > 0 ? Double(recoveredEvents) / Double(dischargeEvents) : nil,
            medianRecoveryHours: median(recoveryHours),
            largestDropVolts: dischargeEvents > 0 ? largestDrop : nil,
            startVoltage: first.voltage,
            endVoltage: last.voltage,
            startDate: first.timestamp,
            endDate: last.timestamp
        )
    }

    public func resetCount(connections: [ConnectionRecord]) -> Int {
        let sorted = connections
            .compactMap { record -> (Date, Int)? in
                guard let date = record.timestamp, let uptime = record.upTimeSeconds else { return nil }
                return (date, uptime)
            }
            .sorted { $0.0 < $1.0 }

        guard sorted.count > 1 else { return 0 }

        return zip(sorted, sorted.dropFirst()).reduce(0) { count, pair in
            pair.1.1 < pair.0.1 ? count + 1 : count
        }
    }

    public func averageSolarMillivolts(sensors: [SensorRecord]) -> Double? {
        let values = sensors.compactMap { $0.solarMv.map(Double.init) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public func averageSolarMilliamps(sensors: [SensorRecord]) -> Double? {
        let values = sensors.compactMap { $0.solarMa.map(Double.init) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public func solarExposureRate(sensors: [SensorRecord]) -> Double? {
        let samples = sensors.filter { $0.solarMv != nil || $0.solarMa != nil }
        guard !samples.isEmpty else { return nil }
        let exposed = samples.filter { ($0.solarMv ?? 0) > 0 || ($0.solarMa ?? 0) > 0 }
        return Double(exposed.count) / Double(samples.count)
    }

    public func averageTemperatureCelsius(sensors: [SensorRecord]) -> Double? {
        let values = sensors.compactMap(\.tempC)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public func averageActivity(sensors: [SensorRecord]) -> Double? {
        let values = sensors.compactMap(activityValue)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public func cumulativeActivity(sensors: [SensorRecord]) -> Double? {
        let cumulativePoints = sensors
            .compactMap { sample -> (Date, Double)? in
                guard let timestamp = sample.timestamp, let cumulative = sample.actCumulative else { return nil }
                return (timestamp, Double(cumulative))
            }
            .sorted { $0.0 < $1.0 }

        if cumulativePoints.count > 1 {
            let positiveDeltas = zip(cumulativePoints, cumulativePoints.dropFirst())
                .map { earlier, later in max(0, later.1 - earlier.1) }
            let observedDelta = positiveDeltas.reduce(0, +)
            if observedDelta > 0 {
                return observedDelta
            }
            return cumulativePoints.last?.1
        }

        if let onlyCumulative = cumulativePoints.first?.1 {
            return onlyCumulative
        }

        let observedActivity = sensors.compactMap(activityValue)
        guard !observedActivity.isEmpty else { return nil }
        return observedActivity.reduce(0, +)
    }

    public func activityValue(_ sensor: SensorRecord) -> Double? {
        if let activity = sensor.activity {
            return Double(activity)
        }
        if let polarAct = sensor.polarAct {
            return Double(polarAct)
        }
        if let x = sensor.actX, let y = sensor.actY, let z = sensor.actZ {
            return Double(abs(x) + abs(y) + abs(z))
        }
        return nil
    }

    private func isGPSFix(_ location: LocationRecord) -> Bool {
        location.hasUsablePosition && [
            LocationKind.gps.rawValue,
            LocationKind.fastGPS.rawValue,
            LocationKind.assistedGPS.rawValue
        ].contains(location.type.rawValue)
    }

    private func connectionFailed(_ record: ConnectionRecord) -> Bool? {
        var hasOutcome = false
        var failed = false

        for payload in [record.server, record.modem] {
            if let explicitFailure = payload?["failed"]?.boolValue {
                hasOutcome = true
                failed = failed || explicitFailure
            }
            if let explicitSuccess = payload?["success"]?.boolValue {
                hasOutcome = true
                failed = failed || !explicitSuccess
            }
        }

        return hasOutcome ? failed : nil
    }

    private func medianIntervalHours(_ dates: [Date]) -> Double? {
        guard dates.count > 1 else { return nil }
        let intervals = zip(dates, dates.dropFirst()).map { earlier, later in
            later.timeIntervalSince(earlier) / 3_600
        }
        return median(intervals)
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
