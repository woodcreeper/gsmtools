import Foundation

public actor RateLimiter {
    public let capacity: Double
    public let refillRatePerSecond: Double

    private var availableTokens: Double
    private var lastRefill: Date
    private let sleeper: (UInt64) async -> Void

    public init(
        requestsPerMinute: Int = 60,
        burstCapacity: Int? = nil,
        now: Date = Date(),
        sleeper: @escaping (UInt64) async -> Void = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        let capacity = Double(burstCapacity ?? requestsPerMinute)
        self.capacity = capacity
        self.refillRatePerSecond = Double(requestsPerMinute) / 60.0
        self.availableTokens = capacity
        self.lastRefill = now
        self.sleeper = sleeper
    }

    public func acquire() async {
        while true {
            refill()

            if availableTokens >= 1 {
                availableTokens -= 1
                return
            }

            let deficit = 1 - availableTokens
            let waitSeconds = max(0.05, deficit / refillRatePerSecond)
            await sleeper(UInt64(waitSeconds * 1_000_000_000))
        }
    }

    private func refill() {
        let now = Date()
        let elapsed = max(0, now.timeIntervalSince(lastRefill))
        guard elapsed > 0 else { return }
        availableTokens = min(capacity, availableTokens + elapsed * refillRatePerSecond)
        lastRefill = now
    }
}

public struct BackoffPolicy: Sendable {
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    public var jitter: ClosedRange<Double>

    public static let apiDefault = BackoffPolicy(baseDelay: 1, maxDelay: 30, jitter: 0.8...1.25)

    public init(baseDelay: TimeInterval, maxDelay: TimeInterval, jitter: ClosedRange<Double>) {
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    public func delay(forAttempt attempt: Int) -> UInt64 {
        let exponent = max(0, attempt - 1)
        let delay = min(maxDelay, baseDelay * pow(2, Double(exponent)))
        let jittered = delay * Double.random(in: jitter)
        return UInt64(jittered * 1_000_000_000)
    }
}
