import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case devices
    case runs
    case alerts
    case reports
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .devices: return "Devices"
        case .runs: return "Runs"
        case .alerts: return "Alerts"
        case .reports: return "Reports"
        case .projects: return "Projects"
        }
    }

    var systemImage: String {
        switch self {
        case .devices: return "antenna.radiowaves.left.and.right"
        case .runs: return "play.rectangle"
        case .alerts: return "bell.badge"
        case .reports: return "doc.text"
        case .projects: return "folder"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .devices: return "1"
        case .runs: return "2"
        case .alerts: return "3"
        case .reports: return "4"
        case .projects: return "5"
        }
    }
}

enum DeviceSortMode: String, CaseIterable, Identifiable {
    case lastConnection
    case alphabetical
    case mostConnections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastConnection:
            return "Last"
        case .alphabetical:
            return "A-Z"
        case .mostConnections:
            return "Count"
        }
    }

    var fullTitle: String {
        switch self {
        case .lastConnection:
            return "Last connection"
        case .alphabetical:
            return "Alphabetical"
        case .mostConnections:
            return "Most connections"
        }
    }
}

enum StudyWindowMode: String, CaseIterable, Identifiable {
    case allData
    case specificPeriod
    case lastDays
    case comparePeriods
    case compareLastDaysToPrior
    case sinceDeployment
    case comparePrePostDeployment
    case sinceConfigUpdate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allData:
            return "All data"
        case .specificPeriod:
            return "Specific period"
        case .lastDays:
            return "Last X days summary"
        case .comparePeriods:
            return "Compare two periods"
        case .compareLastDaysToPrior:
            return "Last X vs prior X"
        case .sinceDeployment:
            return "Since deployment"
        case .comparePrePostDeployment:
            return "Pre/post deployment"
        case .sinceConfigUpdate:
            return "Since config update"
        }
    }
}

enum RequestedRunScope {
    case currentProject
    case selectedDevices
    case savedGroup
}
