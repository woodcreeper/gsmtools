import Foundation

public struct APIConfiguration: Equatable, Sendable {
    public var baseURL: URL

    public static let defaultBaseURL = APIConfiguration(
        baseURL: URL(string: "https://us-central1-ctt-data-portal.cloudfunctions.net/customerApi/v1")!
    )

    public init(baseURL: URL) {
        self.baseURL = APIConfiguration.normalizedBaseURL(baseURL)
    }

    public static func normalizedBaseURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if !path.hasSuffix("/v1") {
            path += "/v1"
        }
        components.path = path
        return components.url!
    }
}

public struct InstructionsFilter: Sendable {
    public var status: String?
    public var type: String?
    public var start: Date?
    public var end: Date?

    public init(status: String? = nil, type: String? = nil, start: Date? = nil, end: Date? = nil) {
        self.status = status
        self.type = type
        self.start = start
        self.end = end
    }
}

public final class CTTAPIClient: @unchecked Sendable {
    public var configuration: APIConfiguration
    public var rateLimiter: RateLimiter

    private let session: URLSession
    private let tokenProvider: () async throws -> String
    private let backoffPolicy: BackoffPolicy
    private let maxRetryAttempts: Int
    private let sleeper: (UInt64) async -> Void

    public init(
        configuration: APIConfiguration = .defaultBaseURL,
        rateLimiter: RateLimiter = RateLimiter(),
        session: URLSession = .shared,
        tokenProvider: @escaping () async throws -> String,
        backoffPolicy: BackoffPolicy = .apiDefault,
        maxRetryAttempts: Int = 4,
        sleeper: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.configuration = configuration
        self.rateLimiter = rateLimiter
        self.session = session
        self.tokenProvider = tokenProvider
        self.backoffPolicy = backoffPolicy
        self.maxRetryAttempts = maxRetryAttempts
        self.sleeper = sleeper
    }

    public func me() async throws -> User {
        let envelope: APIEnvelope<User> = try await send("me")
        return envelope.data
    }

    public func projects(limit: Int = 100, cursor: String? = nil) async throws -> APIEnvelope<[ProjectListItem]> {
        try await send("projects", query: paginationQuery(limit: limit, cursor: cursor))
    }

    public func allProjects(limit: Int = 1000) async throws -> [ProjectListItem] {
        try await fetchAll(limit: limit) { cursor in
            try await self.projects(limit: limit, cursor: cursor)
        }
    }

    public func project(projectId: String) async throws -> Project {
        let envelope: APIEnvelope<Project> = try await send("projects/\(projectId)")
        return envelope.data
    }

    public func projectDevices(projectId: String, limit: Int = 100, cursor: String? = nil) async throws -> APIEnvelope<[ProjectDeviceListItem]> {
        try await send("projects/\(projectId)/devices", query: paginationQuery(limit: limit, cursor: cursor))
    }

    public func allProjectDevices(projectId: String, limit: Int = 1000) async throws -> [ProjectDeviceListItem] {
        try await fetchAll(limit: limit) { cursor in
            try await self.projectDevices(projectId: projectId, limit: limit, cursor: cursor)
        }
    }

    public func device(imei: String) async throws -> Device {
        let envelope: APIEnvelope<Device> = try await send("devices/\(imei)")
        return envelope.data
    }

    public func locations(imei: String, start: Date, end: Date, limit: Int = 100, cursor: String? = nil) async throws -> APIEnvelope<[LocationRecord]> {
        try await send("devices/\(imei)/locations", query: timeWindowQuery(start: start, end: end, limit: limit, cursor: cursor))
    }

    public func allLocations(imei: String, start: Date, end: Date, limit: Int = 1000) async throws -> [LocationRecord] {
        try await fetchAll(limit: limit) { cursor in
            try await self.locations(imei: imei, start: start, end: end, limit: limit, cursor: cursor)
        }
    }

    public func sensors(imei: String, start: Date, end: Date, limit: Int = 100, cursor: String? = nil) async throws -> APIEnvelope<[SensorRecord]> {
        try await send("devices/\(imei)/sensors", query: timeWindowQuery(start: start, end: end, limit: limit, cursor: cursor))
    }

    public func allSensors(imei: String, start: Date, end: Date, limit: Int = 1000) async throws -> [SensorRecord] {
        try await fetchAll(limit: limit) { cursor in
            try await self.sensors(imei: imei, start: start, end: end, limit: limit, cursor: cursor)
        }
    }

    public func connections(imei: String, start: Date, end: Date, limit: Int = 100, cursor: String? = nil) async throws -> APIEnvelope<[ConnectionRecord]> {
        try await send("devices/\(imei)/connections", query: timeWindowQuery(start: start, end: end, limit: limit, cursor: cursor))
    }

    public func allConnections(imei: String, start: Date, end: Date, limit: Int = 1000) async throws -> [ConnectionRecord] {
        try await fetchAll(limit: limit) { cursor in
            try await self.connections(imei: imei, start: start, end: end, limit: limit, cursor: cursor)
        }
    }

    public func instructions(imei: String, filter: InstructionsFilter = InstructionsFilter(), limit: Int = 100, cursor: String? = nil) async throws -> APIEnvelope<[Instruction]> {
        var query = paginationQuery(limit: limit, cursor: cursor)
        if let status = filter.status {
            query.append(URLQueryItem(name: "status", value: status))
        }
        if let type = filter.type {
            query.append(URLQueryItem(name: "type", value: type))
        }
        if let start = filter.start {
            query.append(URLQueryItem(name: "start", value: TimestampNormalizer.apiString(from: start)))
        }
        if let end = filter.end {
            query.append(URLQueryItem(name: "end", value: TimestampNormalizer.apiString(from: end)))
        }
        return try await send("devices/\(imei)/instructions", query: query)
    }

    public func allInstructions(imei: String, filter: InstructionsFilter = InstructionsFilter(), limit: Int = 1000) async throws -> [Instruction] {
        try await fetchAll(limit: limit) { cursor in
            try await self.instructions(imei: imei, filter: filter, limit: limit, cursor: cursor)
        }
    }

    private func fetchAll<Value: Codable & Sendable>(
        limit: Int,
        maxPages: Int = 10_000,
        page: (String?) async throws -> APIEnvelope<[Value]>
    ) async throws -> [Value] {
        var cursor: String?
        var values: [Value] = []
        var pageCount = 0
        var seenCursors = Set<String>()
        let boundedMaxPages = max(1, maxPages)

        while true {
            try Task.checkCancellation()
            guard pageCount < boundedMaxPages else {
                throw CTTAPIError(
                    statusCode: -1,
                    code: .invalidRequest,
                    message: "Pagination exceeded the local \(boundedMaxPages)-page safety limit.",
                    requestId: ""
                )
            }
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw CTTAPIError(
                    statusCode: -1,
                    code: .invalidRequest,
                    message: "Pagination cursor repeated before the next page could be requested.",
                    requestId: ""
                )
            }

            let envelope = try await page(cursor)
            pageCount += 1
            values.append(contentsOf: envelope.data)
            guard envelope.pagination?.hasMore == true else { break }
            guard let nextCursor = envelope.pagination?.nextCursor, !nextCursor.isEmpty else {
                throw CTTAPIError(
                    statusCode: -1,
                    code: .invalidRequest,
                    message: "Pagination reported more data without a next cursor.",
                    requestId: ""
                )
            }
            guard nextCursor != cursor, !seenCursors.contains(nextCursor) else {
                throw CTTAPIError(
                    statusCode: -1,
                    code: .invalidRequest,
                    message: "Pagination did not advance to a new cursor.",
                    requestId: ""
                )
            }
            cursor = nextCursor
        }

        return values
    }

    private func send<Value: Decodable>(_ endpoint: String, query: [URLQueryItem] = []) async throws -> Value {
        var attempt = 1

        while true {
            try Task.checkCancellation()
            await rateLimiter.acquire()

            let request = try await makeRequest(endpoint: endpoint, query: query)
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

            if (200..<300).contains(statusCode) {
                return try JSONDecoder.api.decode(Value.self, from: data)
            }

            let apiError = decodeAPIError(data: data, statusCode: statusCode)
            if apiError.isRetryable && attempt < maxRetryAttempts {
                await sleeper(backoffPolicy.delay(forAttempt: attempt))
                attempt += 1
                continue
            }

            throw apiError
        }
    }

    private func makeRequest(endpoint: String, query: [URLQueryItem]) async throws -> URLRequest {
        let token = try await tokenProvider()
        var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false)!
        let cleanEndpoint = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = configuration.baseURL.path + "/" + cleanEndpoint
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else {
            throw CTTAPIError(statusCode: -1, code: .invalidRequest, message: "Invalid API URL", requestId: "")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func decodeAPIError(data: Data, statusCode: Int) -> CTTAPIError {
        if let envelope = try? JSONDecoder.api.decode(ErrorEnvelope.self, from: data) {
            return CTTAPIError(
                statusCode: statusCode,
                code: envelope.error.code,
                message: envelope.error.message,
                requestId: envelope.error.requestId
            )
        }

        return CTTAPIError(
            statusCode: statusCode,
            code: .unknown,
            message: HTTPURLResponse.localizedString(forStatusCode: statusCode),
            requestId: ""
        )
    }

    private func paginationQuery(limit: Int, cursor: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(max(1, min(1000, limit))))]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }

    private func timeWindowQuery(start: Date, end: Date, limit: Int, cursor: String?) -> [URLQueryItem] {
        var items = [
            URLQueryItem(name: "start", value: TimestampNormalizer.apiString(from: start)),
            URLQueryItem(name: "end", value: TimestampNormalizer.apiString(from: end))
        ]
        items.append(contentsOf: paginationQuery(limit: limit, cursor: cursor))
        return items
    }
}

public struct CTTAPIError: Error, Equatable, LocalizedError, Sendable {
    public var statusCode: Int
    public var code: CTTErrorCode
    public var message: String
    public var requestId: String

    public var errorDescription: String? {
        requestId.isEmpty ? "\(code.rawValue): \(message)" : "\(code.rawValue): \(message) [\(requestId)]"
    }

    public var isRetryable: Bool {
        code == .rateLimited || code == .serviceUnavailable || statusCode == 429 || statusCode == 503
    }
}

extension JSONDecoder {
    static var api: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
