import Combine
import Foundation
import GSMToolsCore

struct SampleLocationRow: Identifiable, Equatable {
    var id: String
    var projectId: String
    var projectName: String
    var deviceName: String
    var imei: String
    var location: LocationRecord

    var unitLabel: String {
        let trimmedName = deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != imei {
            return "\(trimmedName) · \(String(imei.suffix(5)))"
        }
        return String(imei.suffix(5))
    }

    var timestamp: Date { location.timestamp }
    var typeRawValue: String { location.type.rawValue }
    var sortableLatitude: Double { location.lat ?? -.greatestFiniteMagnitude }
    var sortableLongitude: Double { location.lon ?? -.greatestFiniteMagnitude }
    var sortableTimeToFix: Int { location.timeToFix ?? Int.min }
}

private struct ComparisonPeriodDefaults {
    var primaryStart: Date
    var primaryEnd: Date
    var comparisonStart: Date
    var comparisonEnd: Date

    static func make(now: Date = Date()) -> ComparisonPeriodDefaults {
        let calendar = Calendar.current
        let comparisonEnd = calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86_400)
        let primaryStart = calendar.date(byAdding: .minute, value: 1, to: comparisonEnd) ?? comparisonEnd.addingTimeInterval(60)
        let comparisonStart = calendar.date(byAdding: .day, value: -30, to: comparisonEnd) ?? comparisonEnd.addingTimeInterval(-30 * 86_400)

        return ComparisonPeriodDefaults(
            primaryStart: primaryStart,
            primaryEnd: now,
            comparisonStart: comparisonStart,
            comparisonEnd: comparisonEnd
        )
    }
}

private struct ConfigPeriodDefaults {
    var updateDate: Date
    var beforeStart: Date
    var beforeEnd: Date

    static func make(now: Date = Date()) -> ConfigPeriodDefaults {
        let calendar = Calendar.current
        let updateDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now.addingTimeInterval(-7 * 86_400)
        let beforeEnd = calendar.date(byAdding: .minute, value: -1, to: updateDate) ?? updateDate.addingTimeInterval(-60)
        let beforeStart = calendar.date(byAdding: .day, value: -7, to: beforeEnd) ?? beforeEnd.addingTimeInterval(-7 * 86_400)
        return ConfigPeriodDefaults(updateDate: updateDate, beforeStart: beforeStart, beforeEnd: beforeEnd)
    }
}

@MainActor
final class AppModel: ObservableObject {
    private static let initialComparisonDefaults = ComparisonPeriodDefaults.make()
    private static let initialConfigDefaults = ConfigPeriodDefaults.make()

    @Published var apiKeyInput = ""
    @Published var baseURLString = APIConfiguration.defaultBaseURL.baseURL.absoluteString
    @Published var diskBudgetGB = 5.0
    @Published var baselineWindowCount = BaselineSettings.defaults.minimumPriorWindows
    @Published var baselineDensity = BaselineSettings.defaults.minimumDataDensity
    @Published var retentionMode: RetentionMode = .metricsPlusBoundedRawCache
    @Published var estimatedPagesPerEndpoint = 1
    @Published var deviceSortMode: DeviceSortMode = .lastConnection
    @Published var newTestGroupName = ""
    @Published var selectedTestGroupId: UUID?
    @Published var studyWindowMode: StudyWindowMode = .lastDays
    @Published var lastDays = 30
    @Published var periodStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date().addingTimeInterval(-30 * 86_400)
    @Published var periodEndDate = Date()
    @Published var comparisonPrimaryStartDate = initialComparisonDefaults.primaryStart
    @Published var comparisonPrimaryEndDate = initialComparisonDefaults.primaryEnd
    @Published var comparisonBaselineStartDate = initialComparisonDefaults.comparisonStart
    @Published var comparisonBaselineEndDate = initialComparisonDefaults.comparisonEnd
    @Published var comparisonDays = 30
    @Published var deploymentComparisonDays = 30
    @Published var configUpdateDate = initialConfigDefaults.updateDate
    @Published var configComparisonMode: ConfigComparisonMode = .comparablePriorWindow
    @Published var configBeforeStartDate = initialConfigDefaults.beforeStart
    @Published var configBeforeEndDate = initialConfigDefaults.beforeEnd

    @Published private(set) var user: User?
    @Published private(set) var projects: [ProjectListItem] = []
    @Published private(set) var projectDetailsById: [String: Project] = [:]
    @Published private(set) var devicesByProject: [String: [ProjectDeviceListItem]] = [:]
    @Published private(set) var sampleLocations: [LocationRecord] = []
    @Published private(set) var sampleLocationRows: [SampleLocationRow] = []
    @Published private(set) var runs: [AnalysisRun] = []
    @Published private(set) var testGroups: [TestGroup] = []
    @Published private(set) var reports: [Report] = []
    @Published private(set) var alerts: [AlertFlag] = []
    @Published private(set) var pullEstimate: PullEstimate?
    @Published private(set) var sampleLocationTargetDescription: String?
    @Published private(set) var connectionCountsByIMEI: [String: Int] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadingActivity: String?
    @Published private(set) var statusMessage = "Enter a CTT Personal Access Token to begin."
    @Published private(set) var errorMessage: String?
    @Published var requestedSection: AppSection?
    @Published var requestedRunScope: RequestedRunScope?
    @Published var requestedRunSetupReset: UUID?

    @Published var selectedProjectId: String?
    @Published var selectedIMEIs: Set<String> = []
    @Published var selectedLifelineRunId: UUID?
    @Published var requestedLifelineIMEI: String?
    @Published var completedRunPrompt: AnalysisRun?

    private let keychain = KeychainStore()
    private let rateLimiter = RateLimiter(requestsPerMinute: 60)
    private let estimator = PullEstimator()
    private var database: AppDatabase?

    var selectedProject: ProjectListItem? {
        projects.first { $0.projectId == selectedProjectId }
    }

    var selectedProjectDetail: Project? {
        guard let selectedProjectId else { return nil }
        return projectDetailsById[selectedProjectId]
    }

    var selectedTestGroup: TestGroup? {
        testGroups.first { $0.id == selectedTestGroupId }
    }

    var selectedProjectDevices: [ProjectDeviceListItem] {
        guard let selectedProjectId else { return [] }
        return devicesByProject[selectedProjectId] ?? []
    }

    var cachedDevicesByIMEI: [String: ProjectDeviceListItem] {
        var devices: [String: ProjectDeviceListItem] = [:]
        for projectDevices in devicesByProject.values {
            for device in projectDevices where devices[device.imei] == nil {
                devices[device.imei] = device
            }
        }
        return devices
    }

    var selectedDevicesFromCache: [ProjectDeviceListItem] {
        let devices = cachedDevicesByIMEI
        return selectedIMEIs
            .sorted()
            .map { devices[$0] ?? ProjectDeviceListItem(imei: $0, deviceType: "unknown") }
    }

    var selectedIMEIProjectIds: [String] {
        guard !selectedIMEIs.isEmpty else { return [] }
        var projectIds = Set<String>()
        for (projectId, devices) in devicesByProject {
            if devices.contains(where: { selectedIMEIs.contains($0.imei) }) {
                projectIds.insert(projectId)
            }
        }
        if projectIds.isEmpty, let selectedProjectId {
            projectIds.insert(selectedProjectId)
        }
        return projectIds.sorted { lhs, rhs in
            projectName(for: lhs).localizedCaseInsensitiveCompare(projectName(for: rhs)) == .orderedAscending
        }
    }

    var selectedProjectCount: Int {
        selectedIMEIProjectIds.count
    }

    var selectedProjectSummary: String {
        guard !selectedIMEIs.isEmpty else { return "no projects" }
        let projectIds = selectedIMEIProjectIds
        guard !projectIds.isEmpty else { return "unknown project" }
        if projectIds.count == 1, let projectId = projectIds.first {
            return projectName(for: projectId)
        }
        return "\(projectIds.count) projects"
    }

    func selectedDeviceCount(in projectId: String) -> Int {
        guard let devices = devicesByProject[projectId], !selectedIMEIs.isEmpty else { return 0 }
        return devices.reduce(0) { count, device in
            count + (selectedIMEIs.contains(device.imei) ? 1 : 0)
        }
    }

    func projectName(for projectId: String) -> String {
        projects.first { $0.projectId == projectId }?.name ?? projectId
    }

    var sortedSelectedProjectDevices: [ProjectDeviceListItem] {
        selectedProjectDevices.sorted { lhs, rhs in
            switch deviceSortMode {
            case .lastConnection:
                let lhsDate = lhs.latestConnectionAt.flatMap { try? TimestampNormalizer.parseISO8601($0) }
                let rhsDate = rhs.latestConnectionAt.flatMap { try? TimestampNormalizer.parseISO8601($0) }
                switch (lhsDate, rhsDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                    }
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            case .alphabetical:
                let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if order == .orderedSame {
                    return lhs.imei < rhs.imei
                }
                return order == .orderedAscending
            case .mostConnections:
                let lhsCount = connectionCountsByIMEI[lhs.imei] ?? 0
                let rhsCount = connectionCountsByIMEI[rhs.imei] ?? 0
                if lhsCount == rhsCount {
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
                return lhsCount > rhsCount
            }
        }
    }

    var selectedProjectDeploymentReadiness: DeploymentReadiness {
        deploymentReadiness(for: selectedProjectDevices.map(\.imei))
    }

    func deploymentReadiness(for imeis: [String]) -> DeploymentReadiness {
        let uniqueIMEIs = Array(Set(imeis)).sorted()
        let loaded = deploymentDatesFromCachedProjectDevices(
            projectIds: selectedProjectId.map { [$0] } ?? [],
            imeis: uniqueIMEIs
        )
        return DeploymentReadiness(
            loadedCount: loaded.count,
            totalCount: uniqueIMEIs.count,
            missingIMEIs: uniqueIMEIs.filter { loaded[$0] == nil }
        )
    }

    var lifelineScopeDevices: [ProjectDeviceListItem] {
        guard !selectedIMEIs.isEmpty else { return selectedProjectDevices }
        return selectedDevicesFromCache
    }

    var lifelineRunOptions: [AnalysisRun] {
        matchingLifelineRuns
    }

    private var matchingLifelineRuns: [AnalysisRun] {
        let scopeIMEIs = Set(lifelineScopeDevices.map(\.imei))
        let selectedProjectId = selectedProjectId

        return completedLifelineRuns.filter { run in
            if !scopeIMEIs.isEmpty {
                return !scopeIMEIs.isDisjoint(with: Set(run.selectedIMEIs))
            }
            if let selectedProjectId {
                return run.selectedProjectIds.contains(selectedProjectId)
            }
            return true
        }
    }

    var activeLifelineRun: AnalysisRun? {
        if let selectedLifelineRunId,
           let selectedRun = lifelineRunOptions.first(where: { $0.id == selectedLifelineRunId }) {
            return selectedRun
        }
        return matchingLifelineRuns.first
    }

    var lifelineDevices: [ProjectDeviceListItem] {
        guard let run = activeLifelineRun else {
            return lifelineScopeDevices
        }

        let knownDevices = cachedDevicesByIMEI
        return run.selectedIMEIs.map { imei in
            knownDevices[imei] ?? ProjectDeviceListItem(imei: imei, deviceType: "unknown")
        }
    }

    var latestLifelineRun: AnalysisRun? {
        activeLifelineRun
    }

    var latestLifelineSummariesByIMEI: [String: DeviceAnalysisSummary] {
        guard let summaries = activeLifelineRun?.deviceSummaries else { return [:] }
        return Dictionary(uniqueKeysWithValues: summaries.map { ($0.imei, $0) })
    }

    private var completedLifelineRuns: [AnalysisRun] {
        runs.filter { run in
            [.succeeded, .partial].contains(run.state)
                && run.deviceSummaries?.isEmpty == false
        }
    }

    var hasCredential: Bool {
        (try? keychain.loadToken())?.isEmpty == false
    }

    func bootstrap() async {
        do {
            database = try AppDatabase.applicationSupportDatabase()
            runs = try database?.fetchRuns() ?? []
            testGroups = try database?.fetchTestGroups() ?? []
            reports = try database?.fetchReports() ?? []
            alerts = try database?.fetchAlerts() ?? []
            try attachStoredRunsToMatchingTestGroups()
            if selectedTestGroupId == nil {
                selectedTestGroupId = testGroups.first?.id
            }
            updateEstimate()

            statusMessage = "Ready. Refresh account to use the saved token."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCredentialAndRefresh() async {
        do {
            guard !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppError.missingAPIKey
            }
            try keychain.saveToken(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKeyInput = ""
            await refreshAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearCredential() {
        do {
            try keychain.deleteToken()
            user = nil
            projects = []
            projectDetailsById = [:]
            devicesByProject = [:]
            selectedProjectId = nil
            selectedIMEIs = []
            sampleLocations = []
            sampleLocationRows = []
            sampleLocationTargetDescription = nil
            connectionCountsByIMEI = [:]
            newTestGroupName = ""
            statusMessage = "Token removed from Keychain."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshAccount() async {
        await perform("Refreshing account") {
            let client = try makeClient()
            user = try await client.me()
            projects = try await client.allProjects()
            if selectedProjectId == nil {
                selectedProjectId = projects.first?.projectId
            }
            statusMessage = "Loaded \(projects.count) projects."
            updateEstimate()
        }
    }

    func loadDevicesForSelectedProject() async {
        guard let selectedProjectId else { return }
        await perform("Loading devices") {
            let client = try makeClient()
            async let projectDetail = client.project(projectId: selectedProjectId)
            async let projectDevices = client.allProjectDevices(projectId: selectedProjectId)
            let (detail, devices) = try await (projectDetail, projectDevices)
            projectDetailsById[selectedProjectId] = detail
            devicesByProject[selectedProjectId] = devices
            statusMessage = "Loaded \(devices.count) devices for \(selectedProject?.name ?? "project")."
            updateEstimate()
        }
    }

    func selectProject(_ projectId: String?, loadDevices: Bool = false) async {
        selectedProjectId = projectId
        sampleLocations = []
        sampleLocationRows = []
        sampleLocationTargetDescription = nil
        updateEstimate()

        if loadDevices {
            await loadDevicesForSelectedProject()
        }
    }

    func loadConnectionCountsForSelectedProject(days: Int = 30) async {
        guard let selectedProjectId else { return }
        let devices = selectedProjectDevices
        guard !devices.isEmpty else {
            errorMessage = "Load devices before counting connections."
            return
        }

        await perform("Loading connection counts") {
            let client = try makeClient()
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end.addingTimeInterval(Double(-days) * 86_400)
            var counts = connectionCountsByIMEI

            for (index, device) in devices.enumerated() {
                statusMessage = "Counting connections for \(device.displayName) (\(index + 1)/\(devices.count))."
                let connections = try await client.allConnections(imei: device.imei, start: start, end: end)
                counts[device.imei] = connections.count
                connectionCountsByIMEI = counts
            }

            deviceSortMode = .mostConnections
            statusMessage = "Loaded 30-day connection counts for \(devices.count) devices in \(selectedProject?.name ?? selectedProjectId)."
        }
    }

    func loadSampleLocations() async {
        await perform("Loading sample locations") {
            let client = try makeClient()
            let identity = try await client.me()
            let visibleProjects = try await client.allProjects()

            guard !visibleProjects.isEmpty else {
                throw AppError.noProject
            }

            user = identity
            projects = visibleProjects

            if !selectedIMEIs.isEmpty {
                let targets = try await findSampleLocationTargetsForSelectedDevices(client: client, visibleProjects: visibleProjects)
                guard !targets.isEmpty else {
                    throw AppError.noDevice
                }

                var rows: [SampleLocationRow] = []
                let perDeviceLimit = max(20, min(100, 200 / max(1, targets.count)))
                for (index, target) in targets.enumerated() {
                    statusMessage = "Loading sample locations... \(target.device.displayName) (\(index + 1)/\(targets.count))."
                    let locationsPage = try await client.locations(
                        imei: target.device.imei,
                        start: target.window.start,
                        end: target.window.end,
                        limit: perDeviceLimit
                    )
                    rows.append(contentsOf: sampleRows(target: target, locations: locationsPage.data))
                }

                applySelectedSampleLocationRows(rows, targetCount: targets.count)
                return
            }

            guard let target = try await findSampleLocationTarget(client: client, visibleProjects: visibleProjects) else {
                throw AppError.noDevice
            }
            let locationsPage = try await client.locations(
                imei: target.device.imei,
                start: target.window.start,
                end: target.window.end,
                limit: 100
            )

            if locationsPage.data.isEmpty, target.isSelectedDevice {
                if let fallback = try await findSampleLocationTarget(
                    client: client,
                    visibleProjects: visibleProjects,
                    skipSelectedDevice: true
                ) {
                    let fallbackLocations = try await client.locations(
                        imei: fallback.device.imei,
                        start: fallback.window.start,
                        end: fallback.window.end,
                        limit: 100
                    )
                    try applySampleLocationResult(project: fallback.project, devices: fallback.devices, device: fallback.device, locations: fallbackLocations.data)
                    return
                }
            }

            try applySampleLocationResult(project: target.project, devices: target.devices, device: target.device, locations: locationsPage.data)
        }
    }

    private func findSampleLocationTargetsForSelectedDevices(
        client: CTTAPIClient,
        visibleProjects: [ProjectListItem]
    ) async throws -> [SampleLocationTarget] {
        let selected = selectedIMEIs
        guard !selected.isEmpty else { return [] }

        let projectIds = selectedIMEIProjectIds
        var targetsByIMEI: [String: SampleLocationTarget] = [:]
        let projectLookup = Dictionary(uniqueKeysWithValues: visibleProjects.map { ($0.projectId, $0) })

        for projectId in projectIds {
            guard let project = projectLookup[projectId]
                ?? projects.first(where: { $0.projectId == projectId })
            else {
                continue
            }
            let devices = try await loadDevices(projectId: projectId, client: client)

            for device in devices where selected.contains(device.imei) && targetsByIMEI[device.imei] == nil {
                targetsByIMEI[device.imei] = SampleLocationTarget(
                    project: project,
                    devices: devices,
                    device: device,
                    window: sampleLocationWindow(for: device),
                    isSelectedDevice: true
                )
            }
        }

        return selected.sorted().compactMap { targetsByIMEI[$0] }
    }

    private func findSampleLocationTarget(
        client: CTTAPIClient,
        visibleProjects: [ProjectListItem],
        skipSelectedDevice: Bool = false
    ) async throws -> SampleLocationTarget? {
        let orderedProjects = orderedProjectsForSampleLocations(visibleProjects)
        let maxProjectsToScout = 25

        for (index, project) in orderedProjects.prefix(maxProjectsToScout).enumerated() {
            statusMessage = "Loading sample locations... scouting \(project.name) (\(index + 1)/\(min(maxProjectsToScout, orderedProjects.count)))."

            let devices = try await loadDevices(projectId: project.projectId, client: client)
            guard !devices.isEmpty else { continue }

            let selectedDevice = skipSelectedDevice ? nil : devices.first { selectedIMEIs.contains($0.imei) }
            if let selectedDevice {
                return SampleLocationTarget(
                    project: project,
                    devices: devices,
                    device: selectedDevice,
                    window: sampleLocationWindow(for: selectedDevice),
                    isSelectedDevice: true
                )
            }

            if let deviceWithKnownLocation = devices.first(where: { $0.latestLocationAt != nil }) {
                return SampleLocationTarget(
                    project: project,
                    devices: devices,
                    device: deviceWithKnownLocation,
                    window: sampleLocationWindow(for: deviceWithKnownLocation),
                    isSelectedDevice: false
                )
            }
        }

        if skipSelectedDevice {
            return nil
        }

        throw AppError.noDeviceWithLocationsFound(maxProjectsToScout)
    }

    private func orderedProjectsForSampleLocations(_ visibleProjects: [ProjectListItem]) -> [ProjectListItem] {
        guard let selectedProject else { return visibleProjects }
        return [selectedProject] + visibleProjects.filter { $0.projectId != selectedProject.projectId }
    }

    private func loadDevices(projectId: String, client: CTTAPIClient) async throws -> [ProjectDeviceListItem] {
        if let cached = devicesByProject[projectId] {
            return cached
        }
        let devices = try await client.projectDevices(projectId: projectId, limit: 100).data
        devicesByProject[projectId] = devices
        return devices
    }

    private func sampleLocationWindow(for device: ProjectDeviceListItem) -> DateInterval {
        if let latestLocationAt = device.latestLocationAt,
           let latest = try? TimestampNormalizer.parseISO8601(latestLocationAt) {
            let start = Calendar.current.date(byAdding: .day, value: -14, to: latest) ?? latest.addingTimeInterval(-14 * 86_400)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: latest) ?? latest.addingTimeInterval(86_400)
            return DateInterval(start: start, end: end)
        }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-7 * 86_400)
        return DateInterval(start: start, end: end)
    }

    private func applySampleLocationResult(project: ProjectListItem, devices: [ProjectDeviceListItem], device: ProjectDeviceListItem, locations: [LocationRecord]) throws {
        selectedProjectId = project.projectId
        devicesByProject[project.projectId] = devices
        sampleLocations = locations
        sampleLocationRows = sampleRows(
            target: SampleLocationTarget(
                project: project,
                devices: devices,
                device: device,
                window: sampleLocationWindow(for: device),
                isSelectedDevice: false
            ),
            locations: locations
        )
        sampleLocationTargetDescription = "\(project.name) / \(device.displayName) (\(device.imei))"
        statusMessage = "Loaded \(locations.count) sample location records for \(device.displayName)."
        updateEstimate()
    }

    private func applySelectedSampleLocationRows(_ rows: [SampleLocationRow], targetCount: Int) {
        sampleLocationRows = rows
        sampleLocations = rows.map(\.location)
        sampleLocationTargetDescription = "\(targetCount) selected transmitters · \(rows.count) sample locations"
        statusMessage = "Loaded \(rows.count) sample location records across \(targetCount) selected transmitters."
        updateEstimate()
    }

    private func sampleRows(target: SampleLocationTarget, locations: [LocationRecord]) -> [SampleLocationRow] {
        locations.map { location in
            SampleLocationRow(
                id: "\(target.device.imei)-\(location.id)",
                projectId: target.project.projectId,
                projectName: target.project.name,
                deviceName: target.device.displayName,
                imei: target.device.imei,
                location: location
            )
        }
    }

    func createTestGroupFromSelection() {
        let trimmedName = newTestGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Enter a test group name."
            return
        }
        let projectIds = selectedIMEIProjectIds
        guard !projectIds.isEmpty else {
            errorMessage = "Load the selected devices' project before creating a group."
            return
        }
        guard !selectedIMEIs.isEmpty else {
            errorMessage = "Select at least one device for the test group."
            return
        }

        let now = Date()
        let group = TestGroup(
            name: trimmedName,
            projectIds: projectIds,
            deviceIMEIs: Array(selectedIMEIs).sorted(),
            createdAt: now,
            updatedAt: now
        )

        do {
            try database?.saveTestGroup(group)
            testGroups.insert(group, at: 0)
            selectedTestGroupId = group.id
            try attachStoredRunsToMatchingTestGroups()
            newTestGroupName = ""
            updateEstimate()
            statusMessage = "Created test group \(group.name) with \(group.deviceIMEIs.count) devices."
            requestedRunScope = .savedGroup
            requestedSection = .runs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSelection(to group: TestGroup) {
        guard !selectedIMEIs.isEmpty else {
            errorMessage = "Select at least one device to add."
            return
        }
        let projectIds = selectedIMEIProjectIds
        guard !projectIds.isEmpty else {
            errorMessage = "Load the selected devices' project before adding to a group."
            return
        }

        var updated = group
        updated.projectIds = Array(Set(updated.projectIds + projectIds)).sorted()
        updated.deviceIMEIs = Array(Set(updated.deviceIMEIs + selectedIMEIs)).sorted()
        updated.updatedAt = Date()

        do {
            try database?.saveTestGroup(updated)
            upsertTestGroup(updated)
            selectedTestGroupId = updated.id
            try attachStoredRunsToMatchingTestGroups()
            updateEstimate()
            statusMessage = "Updated \(updated.name): \(updated.deviceIMEIs.count) devices."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteTestGroup(_ group: TestGroup) {
        do {
            try database?.deleteTestGroup(id: group.id)
            testGroups.removeAll { $0.id == group.id }
            if selectedTestGroupId == group.id {
                selectedTestGroupId = testGroups.first?.id
            }
            updateEstimate()
            statusMessage = "Deleted test group \(group.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectTestGroup(_ group: TestGroup) {
        selectedTestGroupId = group.id
        updateEstimate()
    }

    func runTestGroup(_ group: TestGroup) async {
        guard !group.deviceIMEIs.isEmpty else {
            errorMessage = "Test group \(group.name) has no devices."
            return
        }

        await runCohort(
            groupName: group.name,
            projectIds: group.projectIds,
            imeis: group.deviceIMEIs,
            existingGroup: group,
            notesSubject: "test group \(group.name)"
        )
    }

    func runFleetHealthForSelectedProject() async {
        guard let selectedProject else {
            errorMessage = AppError.noProject.localizedDescription
            return
        }
        if selectedProjectDevices.isEmpty {
            await loadDevicesForSelectedProject()
        }

        let devices = selectedProjectDevices
        guard !devices.isEmpty else {
            if errorMessage == nil {
                errorMessage = "No devices are available for \(selectedProject.name)."
            }
            return
        }

        await runCohort(
            groupName: "Fleet health - \(selectedProject.name)",
            projectIds: [selectedProject.projectId],
            imeis: devices.map(\.imei),
            existingGroup: matchingTestGroup(projectIds: [selectedProject.projectId], imeis: devices.map(\.imei)),
            notesSubject: "fleet health for \(selectedProject.name)"
        )
    }

    func runSelectedDevices() async {
        let imeis = Array(selectedIMEIs).sorted()
        guard !imeis.isEmpty else {
            errorMessage = "Select devices before running selected-unit analysis."
            return
        }
        let projectIds = selectedIMEIProjectIds
        guard !projectIds.isEmpty else {
            errorMessage = "Load the selected devices' project before running selected-unit analysis."
            return
        }

        await runCohort(
            groupName: "Selected units - \(selectedProjectSummary)",
            projectIds: projectIds,
            imeis: imeis,
            existingGroup: matchingTestGroup(projectIds: projectIds, imeis: imeis),
            notesSubject: "selected units in \(selectedProjectSummary)"
        )
    }

    private func runCohort(
        groupName: String,
        projectIds: [String],
        imeis: [String],
        existingGroup: TestGroup?,
        notesSubject: String
    ) async {
        guard !imeis.isEmpty else {
            errorMessage = "This run scope has no devices."
            return
        }

        let now = Date()
        let studyMode: AnalysisStudyMode
        do {
            studyMode = try await studyModeForRun(now: now, projectIds: projectIds, imeis: imeis)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let group: TestGroup
        if var existingGroup {
            existingGroup.updatedAt = now
            group = existingGroup
        } else {
            group = TestGroup(
                name: groupName,
                projectIds: projectIds,
                deviceIMEIs: imeis,
                notes: "Created automatically from the Runs flow.",
                createdAt: now,
                updatedAt: now
            )
        }

        do {
            try database?.saveTestGroup(group)
            upsertTestGroup(group)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        selectedTestGroupId = group.id
        updateEstimate()
        let pullRange = studyMode.pullRange(now: now)
        let run = AnalysisRun(
            testGroupId: group.id,
            name: "\(group.name) Analysis \(Formatters.shortDateTime.string(from: now))",
            selectedProjectIds: group.projectIds,
            selectedIMEIs: group.deviceIMEIs,
            startDate: pullRange.start,
            endDate: pullRange.end,
            analysisMode: studyMode,
            retentionMode: retentionMode,
            notes: "\(studyMode.displayName) for \(notesSubject). Data pulled from \(Formatters.shortDateTime.string(from: pullRange.start)) to \(Formatters.shortDateTime.string(from: pullRange.end))."
        )

        await executeRun(run)
    }

    private func executeRun(_ run: AnalysisRun) async {
        await perform("Running analysis") {
            let estimate = estimate(for: run)
            guard !estimate.exceedsDiskBudget else {
                throw AppError.diskBudgetExceeded(
                    estimatedBytes: estimate.estimatedBytes,
                    budgetBytes: Int64(diskBudgetGB * 1_073_741_824)
                )
            }

            let client = try makeClient()
            let runner = TelemetryPullRunner(client: client)
            let outcome = await runner.run(run) { updatedRun in
                try? self.database?.saveRun(updatedRun)
                self.upsertRun(updatedRun)
                self.statusMessage = "Running analysis... \(Int(updatedRun.progress.fractionComplete * 100))%."
            }

            var completedRun = outcome.run
            completedRun.deviceSummaries = makeDeviceSummaries(for: completedRun, bundles: outcome.bundles)

            try database?.saveRun(completedRun)
            upsertRun(completedRun)
            try recordRawCacheMetadata(runId: completedRun.id, bundles: outcome.bundles)
            if completedRun.retentionMode == .fullTelemetry {
                try database?.saveRawTelemetry(runId: completedRun.id, bundles: outcome.bundles)
            }

            if let report = makeReport(for: completedRun, bundles: outcome.bundles) {
                try database?.saveReport(report)
                reports.insert(report, at: 0)
                for flag in report.flags {
                    try database?.saveAlert(flag)
                    alerts.insert(flag, at: 0)
                }
            }

            if [.succeeded, .partial].contains(completedRun.state),
               completedRun.deviceSummaries?.isEmpty == false {
                selectedLifelineRunId = completedRun.id
                completedRunPrompt = completedRun
            }

            statusMessage = "Analysis \(completedRun.state.rawValue): \(outcome.bundles.count) device bundles."
        }
    }

    func updateEstimate() {
        let deviceCount = selectedTestGroup?.deviceIMEIs.count ?? max(selectedIMEIs.count, selectedProjectDevices.count)
        pullEstimate = estimator.estimate(
            deviceCount: deviceCount,
            estimatedPagesPerEndpoint: estimatedPagesPerEndpoint,
            diskBudgetBytes: Int64(diskBudgetGB * 1_073_741_824),
            retentionMode: retentionMode
        )
    }

    private func estimate(for run: AnalysisRun) -> PullEstimate {
        estimator.estimate(
            deviceCount: run.selectedIMEIs.count,
            estimatedPagesPerEndpoint: estimatedPagesPerEndpoint,
            diskBudgetBytes: Int64(diskBudgetGB * 1_073_741_824),
            retentionMode: run.retentionMode
        )
    }

    func runs(for group: TestGroup) -> [AnalysisRun] {
        runs.filter { run in
            runBelongsToGroup(run, group: group)
        }
    }

    func currentStudyMode(now: Date = Date()) throws -> AnalysisStudyMode {
        switch studyWindowMode {
        case .allData:
            return .allData
        case .specificPeriod:
            try validateWindow(start: periodStartDate, end: periodEndDate, label: "Specific period")
            return .specificPeriod(start: periodStartDate, end: periodEndDate)
        case .lastDays:
            return .lastDays(max(1, lastDays))
        case .comparePeriods:
            try validateWindow(start: comparisonPrimaryStartDate, end: comparisonPrimaryEndDate, label: "Primary period")
            try validateWindow(start: comparisonBaselineStartDate, end: comparisonBaselineEndDate, label: "Comparison period")
            try validateNoOverlap(
                firstStart: comparisonPrimaryStartDate,
                firstEnd: comparisonPrimaryEndDate,
                secondStart: comparisonBaselineStartDate,
                secondEnd: comparisonBaselineEndDate
            )
            return .comparePeriods(
                primaryStart: comparisonPrimaryStartDate,
                primaryEnd: comparisonPrimaryEndDate,
                comparisonStart: comparisonBaselineStartDate,
                comparisonEnd: comparisonBaselineEndDate
            )
        case .compareLastDaysToPrior:
            return .compareLastDaysToPrior(days: max(1, comparisonDays))
        case .sinceDeployment:
            throw AppError.invalidAnalysisWindow("Deployment analysis uses per-device deployment timestamps from the API and is resolved when the run starts.")
        case .comparePrePostDeployment:
            throw AppError.invalidAnalysisWindow("Deployment comparison uses per-device deployment timestamps from the API and is resolved when the run starts.")
        case .sinceConfigUpdate:
            guard configUpdateDate < now else {
                throw AppError.invalidAnalysisWindow("Config update date must be before now.")
            }
            if configComparisonMode == .customBeforeWindow {
                try validateWindow(start: configBeforeStartDate, end: configBeforeEndDate, label: "Before period")
                try validateNoOverlap(
                    firstStart: configUpdateDate,
                    firstEnd: now,
                    secondStart: configBeforeStartDate,
                    secondEnd: configBeforeEndDate
                )
                guard configBeforeEndDate <= configUpdateDate else {
                    throw AppError.invalidAnalysisWindow("The before period must end on or before the config update date.")
                }
            }
            return .sinceConfigUpdate(
                updateDate: configUpdateDate,
                comparisonMode: configComparisonMode,
                beforeStart: configComparisonMode == .customBeforeWindow ? configBeforeStartDate : nil,
                beforeEnd: configComparisonMode == .customBeforeWindow ? configBeforeEndDate : nil
            )
        }
    }

    func repairComparisonPeriodBoundary() {
        let overlaps = comparisonPrimaryStartDate < comparisonBaselineEndDate
            && comparisonBaselineStartDate < comparisonPrimaryEndDate
        guard overlaps else { return }

        let oneMinute: TimeInterval = 60
        if comparisonPrimaryStartDate >= comparisonBaselineStartDate {
            let adjustedPrimaryStart = comparisonBaselineEndDate.addingTimeInterval(oneMinute)
            if adjustedPrimaryStart < comparisonPrimaryEndDate {
                comparisonPrimaryStartDate = adjustedPrimaryStart
            } else {
                comparisonBaselineEndDate = comparisonPrimaryStartDate.addingTimeInterval(-oneMinute)
            }
        } else {
            let adjustedComparisonStart = comparisonPrimaryEndDate.addingTimeInterval(oneMinute)
            if adjustedComparisonStart < comparisonBaselineEndDate {
                comparisonBaselineStartDate = adjustedComparisonStart
            } else {
                comparisonPrimaryEndDate = comparisonBaselineStartDate.addingTimeInterval(-oneMinute)
            }
        }
    }

    func deleteRun(_ run: AnalysisRun) {
        do {
            try database?.deleteRun(id: run.id)
            runs.removeAll { $0.id == run.id }
            reports.removeAll { $0.runId == run.id }
            alerts.removeAll { $0.runId == run.id }
            if selectedLifelineRunId == run.id {
                selectedLifelineRunId = nil
            }
            if completedRunPrompt?.id == run.id {
                completedRunPrompt = nil
            }
            statusMessage = "Deleted analysis run \(run.name)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestNewRunSetup() {
        completedRunPrompt = nil
        requestedRunSetupReset = UUID()
        requestedSection = .runs
    }

    func openResults(for run: AnalysisRun, focusIMEI: String? = nil) {
        var shouldLoadProjectDevices = false
        if let projectId = run.selectedProjectIds.first,
           selectedProjectId != projectId {
            selectedProjectId = projectId
            shouldLoadProjectDevices = devicesByProject[projectId]?.isEmpty != false
        } else if let projectId = run.selectedProjectIds.first {
            shouldLoadProjectDevices = devicesByProject[projectId]?.isEmpty != false
        }
        selectedIMEIs = Set(run.selectedIMEIs)
        selectedLifelineRunId = run.id
        requestedLifelineIMEI = focusIMEI ?? run.selectedIMEIs.first
        completedRunPrompt = nil
        requestedSection = .devices
        if shouldLoadProjectDevices {
            Task { await loadDevicesForSelectedProject() }
        }
    }

    func dismissCompletedRunPrompt() {
        completedRunPrompt = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func presentError(_ message: String) {
        errorMessage = message
    }

    func export(report: Report, format: ReportExportFormat, to url: URL) {
        do {
            try ReportExporter().write(report, format: format, to: url)
            statusMessage = "Exported \(report.title) as \(format.displayName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ activity: String, operation: () async throws -> Void) async {
        isLoading = true
        loadingActivity = activity
        errorMessage = nil
        statusMessage = "\(activity)..."
        defer {
            isLoading = false
            loadingActivity = nil
        }

        do {
            try await operation()
        } catch {
            if isCancellation(error) {
                statusMessage = "Idle."
                return
            }
            errorMessage = error.localizedDescription
            statusMessage = "\(activity) failed."
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private func upsertRun(_ run: AnalysisRun) {
        if let index = runs.firstIndex(where: { $0.id == run.id }) {
            runs[index] = run
        } else {
            runs.insert(run, at: 0)
        }
    }

    private func upsertTestGroup(_ group: TestGroup) {
        if let index = testGroups.firstIndex(where: { $0.id == group.id }) {
            testGroups[index] = group
        } else {
            testGroups.insert(group, at: 0)
        }
        testGroups.sort { $0.updatedAt > $1.updatedAt }
    }

    private func attachStoredRunsToMatchingTestGroups() throws {
        guard !testGroups.isEmpty else { return }

        var updatedRuns = runs
        var changed = false
        for index in updatedRuns.indices where updatedRuns[index].testGroupId == nil {
            guard let group = matchingTestGroup(for: updatedRuns[index]) else { continue }
            updatedRuns[index].testGroupId = group.id
            try database?.saveRun(updatedRuns[index])
            changed = true
        }

        if changed {
            runs = updatedRuns.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func matchingTestGroup(for run: AnalysisRun) -> TestGroup? {
        let runProjectIds = Set(run.selectedProjectIds)
        let runIMEIs = Set(run.selectedIMEIs)
        let matches = testGroups.filter { group in
            Set(group.projectIds) == runProjectIds && Set(group.deviceIMEIs) == runIMEIs
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private func matchingTestGroup(projectIds: [String], imeis: [String]) -> TestGroup? {
        let projectSet = Set(projectIds)
        let imeiSet = Set(imeis)
        let matches = testGroups.filter { group in
            Set(group.projectIds) == projectSet && Set(group.deviceIMEIs) == imeiSet
        }
        return matches.first
    }

    private func validateWindow(start: Date, end: Date, label: String) throws {
        guard start < end else {
            throw AppError.invalidAnalysisWindow("\(label) start must be before its end.")
        }
    }

    private func validateNoOverlap(firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date) throws {
        let overlaps = firstStart < secondEnd && secondStart < firstEnd
        if overlaps {
            throw AppError.invalidAnalysisWindow("Comparison periods cannot overlap.")
        }
    }

    private func studyModeForRun(now: Date, projectIds: [String], imeis: [String]) async throws -> AnalysisStudyMode {
        switch studyWindowMode {
        case .sinceDeployment:
            return .sinceDeviceDeployments(
                deploymentsByIMEI: try await deploymentDatesByIMEI(projectIds: projectIds, imeis: imeis, now: now)
            )
        case .comparePrePostDeployment:
            return .compareDeviceDeploymentWindows(
                deploymentsByIMEI: try await deploymentDatesByIMEI(projectIds: projectIds, imeis: imeis, now: now),
                days: max(1, deploymentComparisonDays)
            )
        default:
            return try currentStudyMode(now: now)
        }
    }

    private func deploymentDatesByIMEI(projectIds: [String], imeis: [String], now: Date) async throws -> [String: Date] {
        let uniqueIMEIs = Array(Set(imeis)).sorted()
        var dates = deploymentDatesFromCachedProjectDevices(projectIds: projectIds, imeis: uniqueIMEIs)
        let missingFromProjectLists = uniqueIMEIs.filter { dates[$0] == nil }

        if !missingFromProjectLists.isEmpty {
            let client = try makeClient()
            for imei in missingFromProjectLists {
                let detail = try await client.device(imei: imei)
                if let deploymentDate = deploymentDate(from: detail, preferredProjectIds: projectIds) {
                    dates[imei] = deploymentDate
                }
            }
        }

        let missing = uniqueIMEIs.filter { dates[$0] == nil }
        if !missing.isEmpty {
            throw AppError.invalidAnalysisWindow(
                "Deployment analysis requires per-device deployment timestamps from the API. Missing deployment data for \(missing.prefix(5).joined(separator: ", "))\(missing.count > 5 ? "..." : "")."
            )
        }

        let future = dates
            .filter { $0.value >= now }
            .map(\.key)
            .sorted()
        if !future.isEmpty {
            throw AppError.invalidAnalysisWindow(
                "Deployment timestamps must be before now. Future deployment data for \(future.prefix(5).joined(separator: ", "))\(future.count > 5 ? "..." : "")."
            )
        }

        return dates
    }

    private func deploymentDatesFromCachedProjectDevices(projectIds: [String], imeis: [String]) -> [String: Date] {
        let targetIMEIs = Set(imeis)
        let preferredProjectIds = projectIds.filter { devicesByProject[$0] != nil }
        let fallbackProjectIds = devicesByProject.keys
            .filter { !preferredProjectIds.contains($0) }
            .sorted()
        let orderedProjectIds = preferredProjectIds + fallbackProjectIds
        var dates: [String: Date] = [:]

        for projectId in orderedProjectIds {
            for device in devicesByProject[projectId] ?? [] where targetIMEIs.contains(device.imei) && dates[device.imei] == nil {
                if let deploymentDate = device.deploymentTimestamp {
                    dates[device.imei] = deploymentDate
                }
            }
        }

        return dates
    }

    private func deploymentDate(from device: Device, preferredProjectIds: [String]) -> Date? {
        for projectId in preferredProjectIds {
            if let deploymentDate = device.projectInfo[projectId]?.deploymentTimestamp {
                return deploymentDate
            }
        }

        return device.deploymentTimestamp
            ?? device.projectInfo.values.compactMap(\.deploymentTimestamp).sorted().first
    }

    private func loadProjectDetail(projectId: String) async throws -> Project {
        if let cached = projectDetailsById[projectId] {
            return cached
        }
        let client = try makeClient()
        let detail = try await client.project(projectId: projectId)
        projectDetailsById[projectId] = detail
        return detail
    }

    private func runBelongsToGroup(_ run: AnalysisRun, group: TestGroup) -> Bool {
        if let testGroupId = run.testGroupId {
            return testGroupId == group.id
        }

        return Set(run.selectedProjectIds) == Set(group.projectIds)
            && Set(run.selectedIMEIs) == Set(group.deviceIMEIs)
    }

    private func recordRawCacheMetadata(runId: UUID, bundles: [TelemetryBundle]) throws {
        for bundle in bundles {
            try database?.recordRawCacheEntry(
                runId: runId,
                imei: bundle.imei,
                endpoint: "locations",
                recordCount: bundle.locations.count,
                byteCount: Int64(bundle.locations.count * 768)
            )
            try database?.recordRawCacheEntry(
                runId: runId,
                imei: bundle.imei,
                endpoint: "sensors",
                recordCount: bundle.sensors.count,
                byteCount: Int64(bundle.sensors.count * 768)
            )
            try database?.recordRawCacheEntry(
                runId: runId,
                imei: bundle.imei,
                endpoint: "connections",
                recordCount: bundle.connections.count,
                byteCount: Int64(bundle.connections.count * 1_024)
            )
            try database?.recordRawCacheEntry(
                runId: runId,
                imei: bundle.imei,
                endpoint: "instructions",
                recordCount: bundle.instructions.count,
                byteCount: Int64(bundle.instructions.count * 1_024)
            )
        }
    }

    private func makeDeviceSummaries(for run: AnalysisRun, bundles: [TelemetryBundle]) -> [DeviceAnalysisSummary] {
        let calculator = MetricCalculator()

        return bundles.map { bundle in
            let fallbackWindows = [
                AnalysisWindow(id: "period", title: "Selected period", startDate: run.startDate, endDate: run.endDate)
            ]
            let modeWindows = run.analysisMode?.windows(for: bundle.imei, now: run.endDate) ?? fallbackWindows
            let requestedWindows = modeWindows.isEmpty ? fallbackWindows : modeWindows
            let windows = requestedWindows.map {
                $0.replacingSyntheticAllDataBounds(with: observedTimestamps(in: bundle, constrainedTo: $0.interval))
            }
            let currentWindow = currentAnalysisWindow(from: windows)
                ?? AnalysisWindow(id: "period", title: "Selected period", startDate: run.startDate, endDate: run.endDate)

            return DeviceAnalysisSummary(
                imei: bundle.imei,
                windows: windows.map { window in
                    makeDeviceWindowMetrics(window: window, bundle: bundle, calculator: calculator)
                },
                lifelineBuckets: makeLifelineBuckets(bundle: bundle, interval: currentWindow.interval),
                fixPoints: makeFixPoints(bundle: bundle, interval: currentWindow.interval),
                batteryPoints: makeBatteryPoints(bundle: bundle),
                totalLocations: bundle.locations.count,
                totalSensors: bundle.sensors.count,
                totalConnections: bundle.connections.count,
                generatedAt: run.updatedAt
            )
        }
    }

    private func makeDeviceWindowMetrics(
        window: AnalysisWindow,
        bundle: TelemetryBundle,
        calculator: MetricCalculator
    ) -> DeviceWindowMetrics {
        let interval = window.interval
        let locations = bundle.locations.filter { interval.contains($0.timestamp) }
        let sensors = bundle.sensors.filter { sample in
            guard let timestamp = sample.timestamp else { return false }
            return interval.contains(timestamp)
        }
        let connections = bundle.connections.filter { connection in
            guard let timestamp = connection.timestamp else { return false }
            return interval.contains(timestamp)
        }

        return DeviceWindowMetrics(
            id: window.id,
            title: window.title,
            startDate: window.startDate,
            endDate: window.endDate,
            gpsFixCount: locations.filter(isGPSFix).count,
            fallbackFixCount: locations.filter(isFallbackFix).count,
            gpsSuccessRate: calculator.gpsSuccessRate(locations: locations, connections: connections),
            gpsFailureRate: calculator.gpsFailureRate(locations: locations, connections: connections),
            gpsFixCadenceHours: calculator.medianTimeBetweenFixesHours(locations: locations),
            medianTimeToFixSeconds: calculator.medianTimeToFixSeconds(locations: locations),
            connectionCount: calculator.connectionCount(connections: connections),
            connectionFailureRate: calculator.connectionFailureRate(connections: connections),
            checkInCadenceHours: calculator.medianCheckInCadenceHours(connections: connections),
            batteryTrendVoltsPerDay: calculator.batteryTrendVoltsPerDay(sensors: sensors),
            medianBatteryVoltage: calculator.medianBatteryVoltage(sensors: sensors),
            solarMillivolts: calculator.averageSolarMillivolts(sensors: sensors),
            solarMilliamps: calculator.averageSolarMilliamps(sensors: sensors),
            solarExposureRate: calculator.solarExposureRate(sensors: sensors),
            temperatureCelsius: calculator.averageTemperatureCelsius(sensors: sensors),
            activityMean: calculator.averageActivity(sensors: sensors),
            activityCumulative: calculator.cumulativeActivity(sensors: sensors),
            resetCount: calculator.resetCount(connections: connections)
        )
    }

    private func currentAnalysisWindow(from windows: [AnalysisWindow]) -> AnalysisWindow? {
        windows.first { ["primary", "recent", "period", "all"].contains($0.id) } ?? windows.first
    }

    private func observedTimestamps(in bundle: TelemetryBundle, constrainedTo interval: DateInterval) -> [Date] {
        let locationTimestamps = bundle.locations
            .map(\.timestamp)
            .filter { interval.contains($0) }
        let connectionTimestamps = bundle.connections
            .compactMap(\.timestamp)
            .filter { interval.contains($0) }
        let sensorTimestamps = bundle.sensors
            .compactMap(\.timestamp)
            .filter { interval.contains($0) }
        return locationTimestamps + connectionTimestamps + sensorTimestamps
    }

    private func makeLifelineBuckets(bundle: TelemetryBundle, interval: DateInterval) -> [DeviceLifelineBucket] {
        let bucketCount = 32
        let startDate = interval.start
        let endDate = interval.end
        let duration = max(1, endDate.timeIntervalSince(startDate))

        return (0..<bucketCount).map { index in
            let bucketStart = startDate.addingTimeInterval(duration * Double(index) / Double(bucketCount))
            let bucketEnd = startDate.addingTimeInterval(duration * Double(index + 1) / Double(bucketCount))
            let interval = DateInterval(start: bucketStart, end: bucketEnd)
            let locations = bundle.locations.filter { interval.contains($0.timestamp) }
            let connections = bundle.connections.filter { connection in
                guard let timestamp = connection.timestamp else { return false }
                return interval.contains(timestamp)
            }

            return DeviceLifelineBucket(
                id: index,
                startDate: bucketStart,
                endDate: bucketEnd,
                gpsFixCount: locations.filter(isGPSFix).count,
                fallbackFixCount: locations.filter(isFallbackFix).count,
                connectionCount: connections.count
            )
        }
    }

    private func makeFixPoints(bundle: TelemetryBundle, interval: DateInterval) -> [DeviceFixPoint] {
        let positioned = bundle.locations
            .filter { $0.hasUsablePosition && interval.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
        let step = max(1, Int(ceil(Double(positioned.count) / 80.0)))

        return positioned.enumerated().compactMap { offset, location in
            guard offset.isMultiple(of: step),
                  let lat = location.lat,
                  let lon = location.lon
            else {
                return nil
            }

            return DeviceFixPoint(
                id: offset,
                timestamp: location.timestamp,
                lat: lat,
                lon: lon,
                isFallback: isFallbackFix(location),
                type: location.type,
                timeToFix: location.timeToFix,
                hdop: location.hdop,
                satCount: location.satCount,
                uncertaintyM: location.uncertaintyM
            )
        }
    }

    private func makeBatteryPoints(bundle: TelemetryBundle) -> [DeviceBatteryPoint] {
        let voltageSamples = bundle.sensors
            .compactMap { sample -> (Date, Double, Int?, Int?)? in
                guard let timestamp = sample.timestamp, let voltage = sample.battery_v else { return nil }
                return (timestamp, voltage, sample.solarMv, sample.solarMa)
            }
            .sorted { $0.0 < $1.0 }
        let step = max(1, Int(ceil(Double(voltageSamples.count) / 180.0)))

        return voltageSamples.enumerated().compactMap { offset, sample in
            guard offset.isMultiple(of: step) else { return nil }
            return DeviceBatteryPoint(
                id: offset,
                timestamp: sample.0,
                voltage: sample.1,
                solarMillivolts: sample.2,
                solarMilliamps: sample.3
            )
        }
    }

    private func isGPSFix(_ location: LocationRecord) -> Bool {
        location.hasUsablePosition && [
            LocationKind.gps.rawValue,
            LocationKind.fastGPS.rawValue,
            LocationKind.assistedGPS.rawValue
        ].contains(location.type.rawValue)
    }

    private func isFallbackFix(_ location: LocationRecord) -> Bool {
        location.hasUsablePosition && !isGPSFix(location)
    }

    private func makeReport(for run: AnalysisRun, bundles: [TelemetryBundle]) -> Report? {
        guard !bundles.isEmpty else { return nil }
        let calculator = MetricCalculator()
        let nestingDetector = NestingDetector()
        var metrics: [MetricSnapshot] = []
        var flags: [AlertFlag] = []

        for window in makeReportMetricWindows(for: run, bundles: bundles) {
            let locations = window.locations
            let sensors = window.sensors
            let connections = window.connections

            metrics.append(MetricSnapshot(metric: .gpsFixCount, value: Double(calculator.gpsFixCount(locations: locations)), unit: "count", windowStart: window.startDate, windowEnd: window.endDate))
            if let failureRate = calculator.gpsFailureRate(locations: locations, connections: connections) {
                metrics.append(MetricSnapshot(metric: .gpsFailureRate, value: failureRate, unit: "ratio", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let successRate = calculator.gpsSuccessRate(locations: locations, connections: connections) {
                metrics.append(MetricSnapshot(metric: .gpsSuccessRate, value: successRate, unit: "ratio", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let cadence = calculator.medianTimeBetweenFixesHours(locations: locations) {
                metrics.append(MetricSnapshot(metric: .gpsFixCadenceHours, value: cadence, unit: "hours", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let timeToFix = calculator.medianTimeToFixSeconds(locations: locations) {
                metrics.append(MetricSnapshot(metric: .medianTimeToFixSeconds, value: timeToFix, unit: "seconds", windowStart: window.startDate, windowEnd: window.endDate))
            }
            metrics.append(MetricSnapshot(metric: .connectionCount, value: Double(calculator.connectionCount(connections: connections)), unit: "count", windowStart: window.startDate, windowEnd: window.endDate))
            if let connectionFailure = calculator.connectionFailureRate(connections: connections) {
                metrics.append(MetricSnapshot(metric: .connectionFailureRate, value: connectionFailure, unit: "ratio", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let checkInCadence = calculator.medianCheckInCadenceHours(connections: connections) {
                metrics.append(MetricSnapshot(metric: .checkInCadenceHours, value: checkInCadence, unit: "hours", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let batteryTrend = calculator.batteryTrendVoltsPerDay(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .batteryTrendVoltsPerDay, value: batteryTrend, unit: "V/day", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let medianBattery = calculator.medianBatteryVoltage(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .medianBatteryVoltage, value: medianBattery, unit: "V", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let solar = calculator.averageSolarMillivolts(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .solarMillivolts, value: solar, unit: "mV", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let solarMa = calculator.averageSolarMilliamps(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .solarMilliamps, value: solarMa, unit: "mA", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let exposure = calculator.solarExposureRate(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .solarExposureRate, value: exposure, unit: "ratio", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let temp = calculator.averageTemperatureCelsius(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .temperatureCelsius, value: temp, unit: "C", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let activity = calculator.averageActivity(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .activityMean, value: activity, unit: "activity", windowStart: window.startDate, windowEnd: window.endDate))
            }
            if let cumulativeActivity = calculator.cumulativeActivity(sensors: sensors) {
                metrics.append(MetricSnapshot(metric: .activityCumulative, value: cumulativeActivity, unit: "activity", windowStart: window.startDate, windowEnd: window.endDate))
            }

            let resets = calculator.resetCount(connections: connections)
            metrics.append(MetricSnapshot(metric: .resetCount, value: Double(resets), unit: "count", windowStart: window.startDate, windowEnd: window.endDate))
        }

        for bundle in bundles {
            if let flag = nestingDetector.detect(bundle: bundle, run: run) {
                flags.append(flag)
            }
        }
        flags.append(contentsOf: makeDevicePerformanceFlags(for: run))

        return ReportGenerator().makeReport(
            title: "\(run.name) Summary",
            runId: run.id,
            metrics: metrics,
            flags: flags
        )
    }

    private func makeReportMetricWindows(for run: AnalysisRun, bundles: [TelemetryBundle]) -> [ReportMetricWindow] {
        let fallbackWindows = [
            AnalysisWindow(id: "period", title: "Selected period", startDate: run.startDate, endDate: run.endDate)
        ]
        var order: [String] = []
        var windowsById: [String: ReportMetricWindow] = [:]

        for bundle in bundles {
            let candidateWindows = run.analysisMode?.windows(for: bundle.imei, now: run.endDate) ?? fallbackWindows
            let windows = candidateWindows.isEmpty ? fallbackWindows : candidateWindows
            for window in windows {
                if windowsById[window.id] == nil {
                    order.append(window.id)
                    windowsById[window.id] = ReportMetricWindow(id: window.id, title: window.title)
                }

                windowsById[window.id]?.append(window: window, bundle: bundle)
            }
        }

        return order.compactMap { windowsById[$0] }
    }

    private func makeDevicePerformanceFlags(for run: AnalysisRun) -> [AlertFlag] {
        guard let summaries = run.deviceSummaries else { return [] }

        return summaries.flatMap { summary -> [AlertFlag] in
            guard let current = currentWindow(from: summary.windows) else { return [] }
            var flags: [AlertFlag] = []

            if current.connectionCount == 0 && current.gpsFixCount == 0 && current.fallbackFixCount == 0 {
                flags.append(AlertFlag(
                    runId: run.id,
                    imei: summary.imei,
                    metric: .connectionCount,
                    severity: .critical,
                    mode: .threshold,
                    message: "No telemetry records in \(current.title.lowercased())."
                ))
                return flags
            }

            guard let prior = priorWindow(from: summary.windows) else {
                flags.append(AlertFlag(
                    runId: run.id,
                    imei: summary.imei,
                    metric: .gpsSuccessRate,
                    severity: .info,
                    mode: .insufficientBaseline,
                    message: "No comparison baseline was available for \(current.title.lowercased())."
                ))
                return flags
            }

            if current.gpsFixCount == 0 && prior.gpsFixCount > 0 {
                flags.append(AlertFlag(
                    runId: run.id,
                    imei: summary.imei,
                    metric: .gpsFixCount,
                    severity: .critical,
                    mode: .threshold,
                    message: "GPS fixes dropped from \(prior.gpsFixCount) in \(prior.title.lowercased()) to 0 in \(current.title.lowercased())."
                ))
            } else if let currentRate = current.gpsSuccessRate,
                      let priorRate = prior.gpsSuccessRate,
                      priorRate > 0 {
                let drop = (priorRate - currentRate) / priorRate
                if drop >= 0.25 {
                    flags.append(AlertFlag(
                        runId: run.id,
                        imei: summary.imei,
                        metric: .gpsSuccessRate,
                        severity: drop >= 0.50 ? .critical : .warning,
                        mode: .threshold,
                        message: "GPS fix yield fell from \(formatPercent(priorRate)) to \(formatPercent(currentRate))."
                    ))
                }
            }

            if prior.connectionCount > 0 {
                let ratio = Double(current.connectionCount) / Double(prior.connectionCount)
                if ratio <= 0.50 {
                    flags.append(AlertFlag(
                        runId: run.id,
                        imei: summary.imei,
                        metric: .connectionCount,
                        severity: ratio <= 0.25 ? .critical : .warning,
                        mode: .threshold,
                        message: "Connection count fell from \(prior.connectionCount) in \(prior.title.lowercased()) to \(current.connectionCount) in \(current.title.lowercased())."
                    ))
                }
            }

            return flags
        }
    }

    private func currentWindow(from windows: [DeviceWindowMetrics]) -> DeviceWindowMetrics? {
        windows.first { ["primary", "recent", "period", "all"].contains($0.id) } ?? windows.first
    }

    private func priorWindow(from windows: [DeviceWindowMetrics]) -> DeviceWindowMetrics? {
        windows.first { $0.id == "comparison" } ?? windows.dropFirst().first
    }

    private func formatPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func makeClient() throws -> CTTAPIClient {
        guard let baseURL = URL(string: baseURLString) else {
            throw AppError.invalidBaseURL
        }

        let keychain = self.keychain
        return CTTAPIClient(
            configuration: APIConfiguration(baseURL: baseURL),
            rateLimiter: rateLimiter,
            tokenProvider: {
                guard let token = try keychain.loadToken(), !token.isEmpty else {
                    throw AppError.missingAPIKey
                }
                return token
            }
        )
    }
}

enum AppError: Error, LocalizedError {
    case missingAPIKey
    case invalidBaseURL
    case noProject
    case noDevice
    case noDeviceWithLocationsFound(Int)
    case invalidAnalysisWindow(String)
    case diskBudgetExceeded(estimatedBytes: Int64, budgetBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Enter a Personal Access Token first."
        case .invalidBaseURL:
            return "The API base URL is not valid."
        case .noProject:
            return "No accessible project is selected."
        case .noDevice:
            return "No device is available for the selected project."
        case let .noDeviceWithLocationsFound(projectCount):
            return "No device with a known latest location was found in the first \(projectCount) visible projects. Select a specific project/device and load sample locations again."
        case let .invalidAnalysisWindow(message):
            return message
        case let .diskBudgetExceeded(estimatedBytes, budgetBytes):
            return "Estimated pull size \(Self.byteString(estimatedBytes)) exceeds the configured local disk budget of \(Self.byteString(budgetBytes)). Raise the budget or narrow the run before pulling telemetry."
        }
    }

    private static func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct DeploymentReadiness: Equatable {
    var loadedCount: Int
    var totalCount: Int
    var missingIMEIs: [String]

    var hasDevices: Bool { totalCount > 0 }
    var isComplete: Bool { hasDevices && missingIMEIs.isEmpty }

    var statusText: String {
        guard hasDevices else {
            return "No devices in the current scope."
        }
        if isComplete {
            return "\(loadedCount) of \(totalCount) selected devices have API deployment timestamps."
        }
        return "\(loadedCount) of \(totalCount) selected devices expose API deployment timestamps."
    }
}

private struct ReportMetricWindow {
    var id: String
    var title: String
    private var start: Date?
    private var end: Date?
    var locations: [LocationRecord] = []
    var sensors: [SensorRecord] = []
    var connections: [ConnectionRecord] = []

    var startDate: Date { start ?? Date(timeIntervalSince1970: 0) }
    var endDate: Date { end ?? startDate }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    mutating func append(window: AnalysisWindow, bundle: TelemetryBundle) {
        start = min(start ?? window.startDate, window.startDate)
        end = max(end ?? window.endDate, window.endDate)
        let interval = window.interval
        locations.append(contentsOf: bundle.locations.filter { interval.contains($0.timestamp) })
        sensors.append(contentsOf: bundle.sensors.filter { sample in
            guard let timestamp = sample.timestamp else { return false }
            return interval.contains(timestamp)
        })
        connections.append(contentsOf: bundle.connections.filter { connection in
            guard let timestamp = connection.timestamp else { return false }
            return interval.contains(timestamp)
        })
    }
}

private struct SampleLocationTarget {
    var project: ProjectListItem
    var devices: [ProjectDeviceListItem]
    var device: ProjectDeviceListItem
    var window: DateInterval
    var isSelectedDevice: Bool
}
