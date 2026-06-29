import Foundation

public protocol TelemetryPulling: Sendable {
    func allLocations(imei: String, start: Date, end: Date, limit: Int) async throws -> [LocationRecord]
    func allSensors(imei: String, start: Date, end: Date, limit: Int) async throws -> [SensorRecord]
    func allConnections(imei: String, start: Date, end: Date, limit: Int) async throws -> [ConnectionRecord]
    func allInstructions(imei: String, filter: InstructionsFilter, limit: Int) async throws -> [Instruction]
}

extension CTTAPIClient: TelemetryPulling {}

public struct TelemetryBundle: Codable, Equatable, Sendable {
    public var imei: String
    public var locations: [LocationRecord]
    public var sensors: [SensorRecord]
    public var connections: [ConnectionRecord]
    public var instructions: [Instruction]

    public init(
        imei: String,
        locations: [LocationRecord] = [],
        sensors: [SensorRecord] = [],
        connections: [ConnectionRecord] = [],
        instructions: [Instruction] = []
    ) {
        self.imei = imei
        self.locations = locations
        self.sensors = sensors
        self.connections = connections
        self.instructions = instructions
    }

    public var totalRecordCount: Int {
        locations.count + sensors.count + connections.count + instructions.count
    }
}

public struct PullRunOutcome: Sendable {
    public var run: AnalysisRun
    public var bundles: [TelemetryBundle]
}

public final class TelemetryPullRunner: Sendable {
    private let client: any TelemetryPulling
    private let pageLimit: Int

    public init(client: any TelemetryPulling, pageLimit: Int = 1000) {
        self.client = client
        self.pageLimit = pageLimit
    }

    public func run(
        _ run: AnalysisRun,
        progress: @escaping (AnalysisRun) async -> Void = { _ in }
    ) async -> PullRunOutcome {
        var workingRun = run
        workingRun.state = .running
        workingRun.progress = RunProgress(
            completedRequests: 0,
            estimatedRequests: max(1, run.selectedIMEIs.count * 4),
            deviceResults: run.selectedIMEIs.map {
                DevicePullResult(imei: $0, state: .pending, retryCount: 0, message: nil)
            }
        )
        await progress(workingRun)

        var bundles: [TelemetryBundle] = []

        for imei in run.selectedIMEIs {
            guard !Task.isCancelled else {
                workingRun.state = .canceled
                await progress(workingRun)
                return PullRunOutcome(run: workingRun, bundles: bundles)
            }

            updateDevice(imei: imei, state: .running, message: nil, in: &workingRun)
            await progress(workingRun)

            do {
                let bundle = try await pullDevice(imei: imei, start: run.startDate, end: run.endDate)
                bundles.append(bundle)
                updateDevice(imei: imei, state: .succeeded, message: "\(bundle.totalRecordCount) records", in: &workingRun)
            } catch {
                updateDevice(imei: imei, state: .failed, message: error.localizedDescription, in: &workingRun)
            }

            workingRun.progress.completedRequests = min(
                workingRun.progress.estimatedRequests,
                workingRun.progress.completedRequests + 4
            )
            workingRun.updatedAt = Date()
            await progress(workingRun)
        }

        let failedCount = workingRun.progress.deviceResults.filter { $0.state == .failed }.count
        if failedCount == 0 {
            workingRun.state = .succeeded
        } else if failedCount == workingRun.progress.deviceResults.count {
            workingRun.state = .failed
        } else {
            workingRun.state = .partial
        }
        workingRun.updatedAt = Date()
        await progress(workingRun)

        return PullRunOutcome(run: workingRun, bundles: bundles)
    }

    private func pullDevice(imei: String, start: Date, end: Date) async throws -> TelemetryBundle {
        async let locations = client.allLocations(imei: imei, start: start, end: end, limit: pageLimit)
        async let sensors = client.allSensors(imei: imei, start: start, end: end, limit: pageLimit)
        async let connections = client.allConnections(imei: imei, start: start, end: end, limit: pageLimit)
        async let instructions = client.allInstructions(
            imei: imei,
            filter: InstructionsFilter(start: start, end: end),
            limit: pageLimit
        )

        return try await TelemetryBundle(
            imei: imei,
            locations: locations,
            sensors: sensors,
            connections: connections,
            instructions: instructions
        )
    }

    private func updateDevice(imei: String, state: DevicePullState, message: String?, in run: inout AnalysisRun) {
        guard let index = run.progress.deviceResults.firstIndex(where: { $0.imei == imei }) else { return }
        run.progress.deviceResults[index].state = state
        run.progress.deviceResults[index].message = message
    }
}
