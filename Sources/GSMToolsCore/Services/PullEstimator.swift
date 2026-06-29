import Foundation

public struct PullEstimator: Sendable {
    public var requestsPerMinute: Int
    public var bytesPerRecordEstimate: Int64

    public init(requestsPerMinute: Int = 60, bytesPerRecordEstimate: Int64 = 768) {
        self.requestsPerMinute = requestsPerMinute
        self.bytesPerRecordEstimate = bytesPerRecordEstimate
    }

    public func estimate(
        deviceCount: Int,
        endpointCount: Int = 4,
        estimatedPagesPerEndpoint: Int = 1,
        estimatedRecordsPerPage: Int = 100,
        diskBudgetBytes: Int64,
        retentionMode: RetentionMode
    ) -> PullEstimate {
        let boundedDeviceCount = max(0, deviceCount)
        let boundedEndpointCount = max(0, endpointCount)
        let boundedPages = max(1, estimatedPagesPerEndpoint)
        let requestCount = boundedDeviceCount * boundedEndpointCount * boundedPages
        let duration = Double(requestCount) / Double(max(1, requestsPerMinute)) * 60.0

        let bytes: Int64
        switch retentionMode {
        case .metricsPlusBoundedRawCache:
            bytes = Int64(requestCount * estimatedRecordsPerPage) * bytesPerRecordEstimate / 4
        case .fullTelemetry:
            bytes = Int64(requestCount * estimatedRecordsPerPage) * bytesPerRecordEstimate
        }

        return PullEstimate(
            deviceCount: boundedDeviceCount,
            endpointCount: boundedEndpointCount,
            estimatedPagesPerEndpoint: boundedPages,
            estimatedRequests: requestCount,
            estimatedMinimumDuration: duration,
            estimatedBytes: bytes,
            exceedsDiskBudget: bytes > diskBudgetBytes
        )
    }
}
