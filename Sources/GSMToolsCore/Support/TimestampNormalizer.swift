import Foundation

public enum TimestampNormalizer {
    private static let isoFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func date(fromEpochMilliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value) / 1_000)
    }

    public static func parseISO8601(_ value: String) throws -> Date {
        if let date = isoFormatterWithFractionalSeconds.date(from: value) ?? isoFormatter.date(from: value) {
            return date
        }

        throw TimestampError.invalidISO8601(value)
    }

    public static func apiString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

public enum TimestampError: Error, Equatable, LocalizedError {
    case invalidISO8601(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidISO8601(value):
            return "Invalid ISO 8601 timestamp: \(value)"
        }
    }
}
