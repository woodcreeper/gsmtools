import Foundation

public struct Scheduler: Sendable {
    public init() {}

    public func dueRuns(from runs: [AnalysisRun], now: Date = Date()) -> [AnalysisRun] {
        runs.filter { run in
            guard run.state != .running && run.state != .canceled else { return false }
            guard let nextDate = nextDueDate(for: run) else { return false }
            return nextDate <= now
        }
    }

    public func nextDueDate(for run: AnalysisRun) -> Date? {
        switch run.schedule {
        case .manual:
            return nil
        case .daily:
            return Calendar.current.date(byAdding: .day, value: 1, to: run.updatedAt)
        case .weekly:
            return Calendar.current.date(byAdding: .day, value: 7, to: run.updatedAt)
        case let .customInterval(hours):
            return Calendar.current.date(byAdding: .hour, value: max(1, hours), to: run.updatedAt)
        }
    }
}
