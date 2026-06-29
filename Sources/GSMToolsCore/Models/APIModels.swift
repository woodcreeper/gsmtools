import Foundation

public struct APIEnvelope<Value: Codable & Sendable>: Codable, Sendable {
    public var data: Value
    public var pagination: PaginationEnvelope?

    public init(data: Value, pagination: PaginationEnvelope? = nil) {
        self.data = data
        self.pagination = pagination
    }
}

public struct PaginationEnvelope: Codable, Equatable, Sendable {
    public var nextCursor: String?
    public var hasMore: Bool

    public init(nextCursor: String?, hasMore: Bool) {
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct ErrorEnvelope: Codable, Equatable, Sendable {
    public var error: APIErrorBody
}

public struct APIErrorBody: Codable, Equatable, Sendable {
    public var code: CTTErrorCode
    public var message: String
    public var requestId: String
}

public enum CTTErrorCode: String, Codable, Equatable, Sendable {
    case unauthorized
    case forbidden
    case notFound = "not_found"
    case rateLimited = "rate_limited"
    case invalidRequest = "invalid_request"
    case methodNotAllowed = "method_not_allowed"
    case serviceUnavailable = "service_unavailable"
    case internalError = "internal"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = CTTErrorCode(rawValue: rawValue) ?? .unknown
    }
}

public struct User: Codable, Equatable, Identifiable, Sendable {
    public var userId: String
    public var email: String?
    public var displayName: String?
    public var role: String
    public var projectCount: Int
    public var tokenId: String

    public var id: String { userId }
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var projectId: String
    public var name: String
    public var description: String?
    public var ownerId: String
    public var createdAt: String?
    public var updatedAt: String?
    public var orderNumber: String?
    public var shippedAt: String?

    public var id: String { projectId }
}

public struct ProjectListItem: Codable, Equatable, Identifiable, Sendable {
    public var projectId: String
    public var name: String
    public var description: String?
    public var ownerId: String
    public var createdAt: String?
    public var updatedAt: String?

    public var id: String { projectId }
}

public struct ProjectDeviceListItem: Codable, Equatable, Identifiable, Sendable {
    public var imei: String
    public var deviceType: String
    public var alias: String?
    public var latestConnectionAt: String?
    public var latestLocationAt: String?
    public var latestBatteryV: Double?
    public var deployedAt: String?
    public var deploymentAt: String?
    public var deploymentDate: String?
    public var deployment: AnyJSON?
    public var deploymentInfo: AnyJSON?

    public init(
        imei: String,
        deviceType: String,
        alias: String? = nil,
        latestConnectionAt: String? = nil,
        latestLocationAt: String? = nil,
        latestBatteryV: Double? = nil,
        deployedAt: String? = nil,
        deploymentAt: String? = nil,
        deploymentDate: String? = nil,
        deployment: AnyJSON? = nil,
        deploymentInfo: AnyJSON? = nil
    ) {
        self.imei = imei
        self.deviceType = deviceType
        self.alias = alias
        self.latestConnectionAt = latestConnectionAt
        self.latestLocationAt = latestLocationAt
        self.latestBatteryV = latestBatteryV
        self.deployedAt = deployedAt
        self.deploymentAt = deploymentAt
        self.deploymentDate = deploymentDate
        self.deployment = deployment
        self.deploymentInfo = deploymentInfo
    }

    public var id: String { imei }
    public var displayName: String { alias?.isEmpty == false ? alias! : imei }
    public var deploymentTimestamp: Date? {
        DeploymentTimestampResolver.parse(
            deployedAt,
            deploymentAt,
            deploymentDate
        ) ?? DeploymentTimestampResolver.parse(json: deployment, deploymentInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case imei
        case deviceType
        case alias
        case latestConnectionAt
        case latestLocationAt
        case latestBatteryV
        case deployedAt
        case deploymentAt
        case deploymentDate
        case deployed_at
        case deployment_at
        case deployment_date
        case deployment
        case deploymentInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imei = try container.decode(String.self, forKey: .imei)
        deviceType = try container.decode(String.self, forKey: .deviceType)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        latestConnectionAt = try container.decodeIfPresent(String.self, forKey: .latestConnectionAt)
        latestLocationAt = try container.decodeIfPresent(String.self, forKey: .latestLocationAt)
        latestBatteryV = try container.decodeIfPresent(Double.self, forKey: .latestBatteryV)
        deployedAt = try container.decodeIfPresent(String.self, forKey: .deployedAt)
            ?? container.decodeIfPresent(String.self, forKey: .deployed_at)
        deploymentAt = try container.decodeIfPresent(String.self, forKey: .deploymentAt)
            ?? container.decodeIfPresent(String.self, forKey: .deployment_at)
        deploymentDate = try container.decodeIfPresent(String.self, forKey: .deploymentDate)
            ?? container.decodeIfPresent(String.self, forKey: .deployment_date)
        deployment = try container.decodeIfPresent(AnyJSON.self, forKey: .deployment)
        deploymentInfo = try container.decodeIfPresent(AnyJSON.self, forKey: .deploymentInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imei, forKey: .imei)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encodeIfPresent(latestConnectionAt, forKey: .latestConnectionAt)
        try container.encodeIfPresent(latestLocationAt, forKey: .latestLocationAt)
        try container.encodeIfPresent(latestBatteryV, forKey: .latestBatteryV)
        try container.encodeIfPresent(deployedAt, forKey: .deployedAt)
        try container.encodeIfPresent(deploymentAt, forKey: .deploymentAt)
        try container.encodeIfPresent(deploymentDate, forKey: .deploymentDate)
        try container.encodeIfPresent(deployment, forKey: .deployment)
        try container.encodeIfPresent(deploymentInfo, forKey: .deploymentInfo)
    }
}

public typealias TelemetryDevice = ProjectDeviceListItem

public struct Device: Codable, Equatable, Identifiable, Sendable {
    public var imei: String
    public var deviceType: String
    public var deviceName: String?
    public var iccid: String?
    public var fw: DeviceFwInfo?
    public var latestConnection: AnyJSON?
    public var latestLocation: AnyJSON?
    public var latestSensor: AnyJSON?
    public var createdAt: String?
    public var projectInfo: [String: DeviceProjectInfoEntry]
    public var deployedAt: String?
    public var deploymentAt: String?
    public var deploymentDate: String?
    public var deployment: AnyJSON?
    public var deploymentInfo: AnyJSON?

    public var id: String { imei }
    public var deploymentTimestamp: Date? {
        DeploymentTimestampResolver.parse(
            deployedAt,
            deploymentAt,
            deploymentDate,
            latestLocation?["deployedAt"]?.stringValue,
            latestLocation?["deploymentAt"]?.stringValue,
            latestLocation?["deploymentDate"]?.stringValue,
            latestLocation?["deployed_at"]?.stringValue,
            latestLocation?["deployment_at"]?.stringValue,
            latestLocation?["deployment_date"]?.stringValue,
            latestSensor?["deployedAt"]?.stringValue,
            latestSensor?["deploymentAt"]?.stringValue,
            latestSensor?["deploymentDate"]?.stringValue,
            latestSensor?["deployed_at"]?.stringValue,
            latestSensor?["deployment_at"]?.stringValue,
            latestSensor?["deployment_date"]?.stringValue
        ) ?? DeploymentTimestampResolver.parse(json: deployment, deploymentInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case imei
        case deviceType
        case deviceName
        case iccid
        case fw
        case latestConnection
        case latestLocation
        case latestSensor
        case createdAt
        case projectInfo
        case deployedAt
        case deploymentAt
        case deploymentDate
        case deployed_at
        case deployment_at
        case deployment_date
        case deployment
        case deploymentInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imei = try container.decode(String.self, forKey: .imei)
        deviceType = try container.decode(String.self, forKey: .deviceType)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        iccid = try container.decodeIfPresent(String.self, forKey: .iccid)
        fw = try container.decodeIfPresent(DeviceFwInfo.self, forKey: .fw)
        latestConnection = try container.decodeIfPresent(AnyJSON.self, forKey: .latestConnection)
        latestLocation = try container.decodeIfPresent(AnyJSON.self, forKey: .latestLocation)
        latestSensor = try container.decodeIfPresent(AnyJSON.self, forKey: .latestSensor)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        projectInfo = try container.decode([String: DeviceProjectInfoEntry].self, forKey: .projectInfo)
        deployedAt = try container.decodeIfPresent(String.self, forKey: .deployedAt)
            ?? container.decodeIfPresent(String.self, forKey: .deployed_at)
        deploymentAt = try container.decodeIfPresent(String.self, forKey: .deploymentAt)
            ?? container.decodeIfPresent(String.self, forKey: .deployment_at)
        deploymentDate = try container.decodeIfPresent(String.self, forKey: .deploymentDate)
            ?? container.decodeIfPresent(String.self, forKey: .deployment_date)
        deployment = try container.decodeIfPresent(AnyJSON.self, forKey: .deployment)
        deploymentInfo = try container.decodeIfPresent(AnyJSON.self, forKey: .deploymentInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imei, forKey: .imei)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encodeIfPresent(iccid, forKey: .iccid)
        try container.encodeIfPresent(fw, forKey: .fw)
        try container.encodeIfPresent(latestConnection, forKey: .latestConnection)
        try container.encodeIfPresent(latestLocation, forKey: .latestLocation)
        try container.encodeIfPresent(latestSensor, forKey: .latestSensor)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encode(projectInfo, forKey: .projectInfo)
        try container.encodeIfPresent(deployedAt, forKey: .deployedAt)
        try container.encodeIfPresent(deploymentAt, forKey: .deploymentAt)
        try container.encodeIfPresent(deploymentDate, forKey: .deploymentDate)
        try container.encodeIfPresent(deployment, forKey: .deployment)
        try container.encodeIfPresent(deploymentInfo, forKey: .deploymentInfo)
    }
}

public struct DeviceFwInfo: Codable, Equatable, Sendable {
    public var major: Int?
    public var minor: Int?
    public var patch: Int?
    public var model: String?
    public var app: String?
}

public struct DeviceProjectInfoEntry: Codable, Equatable, Sendable {
    public var projectName: String?
    public var alias: String?
    public var deployedAt: String?
    public var deploymentAt: String?
    public var deploymentDate: String?
    public var deployment: AnyJSON?
    public var deploymentInfo: AnyJSON?

    public var deploymentTimestamp: Date? {
        DeploymentTimestampResolver.parse(
            deployedAt,
            deploymentAt,
            deploymentDate
        ) ?? DeploymentTimestampResolver.parse(json: deployment, deploymentInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case projectName
        case alias
        case deployedAt
        case deploymentAt
        case deploymentDate
        case deployed_at
        case deployment_at
        case deployment_date
        case deployment
        case deploymentInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        alias = try container.decodeIfPresent(String.self, forKey: .alias)
        deployedAt = try container.decodeIfPresent(String.self, forKey: .deployedAt)
            ?? container.decodeIfPresent(String.self, forKey: .deployed_at)
        deploymentAt = try container.decodeIfPresent(String.self, forKey: .deploymentAt)
            ?? container.decodeIfPresent(String.self, forKey: .deployment_at)
        deploymentDate = try container.decodeIfPresent(String.self, forKey: .deploymentDate)
            ?? container.decodeIfPresent(String.self, forKey: .deployment_date)
        deployment = try container.decodeIfPresent(AnyJSON.self, forKey: .deployment)
        deploymentInfo = try container.decodeIfPresent(AnyJSON.self, forKey: .deploymentInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encodeIfPresent(alias, forKey: .alias)
        try container.encodeIfPresent(deployedAt, forKey: .deployedAt)
        try container.encodeIfPresent(deploymentAt, forKey: .deploymentAt)
        try container.encodeIfPresent(deploymentDate, forKey: .deploymentDate)
        try container.encodeIfPresent(deployment, forKey: .deployment)
        try container.encodeIfPresent(deploymentInfo, forKey: .deploymentInfo)
    }
}

public enum DeploymentTimestampResolver {
    private static let timestampKeys = [
        "deployedAt",
        "deploymentAt",
        "deploymentDate",
        "deployed_at",
        "deployment_at",
        "deployment_date"
    ]

    public static func parse(_ candidates: String?...) -> Date? {
        for candidate in candidates {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  let date = try? TimestampNormalizer.parseISO8601(trimmed)
            else {
                continue
            }
            return date
        }
        return nil
    }

    public static func parse(json candidates: AnyJSON?...) -> Date? {
        for candidate in candidates {
            guard let candidate, let date = parse(candidate) else { continue }
            return date
        }
        return nil
    }

    private static func parse(_ json: AnyJSON) -> Date? {
        if let string = json.stringValue {
            return parse(string)
        }
        for key in timestampKeys {
            if let date = json[key]?.stringValue.flatMap({ parse($0) }) {
                return date
            }
        }
        return parse(json: json["deployment"], json["deploymentInfo"])
    }
}

public struct LocationKind: Codable, Hashable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let gps = LocationKind(rawValue: "gps")
    public static let fastGPS = LocationKind(rawValue: "fast_gps")
    public static let cellLocate = LocationKind(rawValue: "cell_locate")
    public static let argos = LocationKind(rawValue: "argos")
    public static let iridium = LocationKind(rawValue: "iridium")
    public static let assistedGPS = LocationKind(rawValue: "assisted_gps")
    public static let unknown = LocationKind(rawValue: "unknown")
}

public struct LocationRecord: Codable, Equatable, Identifiable, Sendable {
    public var fixAt: Int64
    public var type: LocationKind
    public var lat: Double?
    public var lon: Double?
    public var altM: Double?
    public var groundSpeedKnts: Double?
    public var cog: Double?
    public var hdop: Double?
    public var pdop: Double?
    public var vdop: Double?
    public var satCount: Int?
    public var timeToFix: Int?
    public var navMode: Int?
    public var errorFlag: Int?
    public var reason: Int?
    public var uncertaintyM: Double?

    public var id: String { "\(fixAt)-\(type.rawValue)-\(lat ?? 0)-\(lon ?? 0)" }
    public var timestamp: Date { TimestampNormalizer.date(fromEpochMilliseconds: fixAt) }
    public var hasUsablePosition: Bool { lat != nil && lon != nil }
}

public struct SensorSource: Codable, Hashable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let connection = SensorSource(rawValue: "connection")
    public static let gps = SensorSource(rawValue: "gps")
    public static let sensor = SensorSource(rawValue: "sensor")
}

public struct SensorRecord: Codable, Equatable, Identifiable, Sendable {
    public var imei: String
    public var time: String
    public var source: SensorSource
    public var reason: Int?
    public var battery_v: Double?
    public var solarMv: Int?
    public var solarMa: Int?
    public var tempC: Double?
    public var activity: Int?
    public var actCumulative: Int?
    public var actX: Int?
    public var actY: Int?
    public var actZ: Int?
    public var polarAct: Int?

    public var id: String { "\(imei)-\(time)-\(source.rawValue)" }
    public var timestamp: Date? { try? TimestampNormalizer.parseISO8601(time) }
}

public struct ConnectionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var imei: String
    public var connectAt: String
    public var modem: AnyJSON?
    public var server: AnyJSON?
    public var fw: AnyJSON?
    public var config: AnyJSON?
    public var configNum: Int?
    public var reason: String?
    public var upTimeSeconds: Int?
    public var gpsAttempts: Int?

    public var timestamp: Date? { try? TimestampNormalizer.parseISO8601(connectAt) }
}

public struct Instruction: Codable, Equatable, Identifiable, Sendable {
    public var instructionId: String
    public var deviceId: String
    public var type: String
    public var status: String
    public var configType: String?
    public var assignedAt: String?
    public var deliveredAt: String?
    public var supersededAt: String?
    public var assignedBy: String
    public var assignedByName: String?
    public var deviceSeries: String?
    public var data: AnyJSON?
    public var notes: String?

    public var id: String { instructionId }
}
