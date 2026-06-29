import GSMToolsCore
import SwiftUI

struct RunBuilderView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @State private var question: RunQuestion = .fleetHealth
    @State private var scope: RunScope = .currentProject
    @State private var showLatestStatus = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeaderView(
                    title: "Runs",
                    subtitle: "Choose the question, scope, and period. The app fetches telemetry, then Devices ranks the results."
                )

                FlowStrip(activeStep: activeStep, completedSteps: completedSteps)

                if let completedRun = scopedCompletedPrompt {
                    CompletedRunCallout(run: completedRun)
                }

                QuestionPanel(question: $question, scope: $scope)

                HStack(alignment: .top, spacing: 13) {
                    ScopePanel(scope: $scope)
                        .frame(minWidth: 330, maxWidth: 430)
                    WindowPanel(question: $question, scope: scope)
                }

                HStack(alignment: .top, spacing: 13) {
                    DataBudgetPanel(scope: scope) {
                        showLatestStatus = true
                    }
                        .frame(minWidth: 330, maxWidth: 430)
                    RunProgressPanel(scope: scope, showLatestStatus: $showLatestStatus)
                }

                RunHistoryPanel(scope: scope)
            }
            .padding(18)
        }
        .background(CTTColor.canvas(scheme))
        .onAppear {
            model.studyWindowMode = question.studyMode
            applyRequestedRunScopeIfNeeded()
            consumeRequestedRunSetupReset()
        }
        .onChange(of: model.requestedRunScope) { _, _ in
            applyRequestedRunScopeIfNeeded()
        }
        .onChange(of: model.requestedRunSetupReset) { _, _ in
            consumeRequestedRunSetupReset()
        }
        .onChange(of: setupSignature) { _, _ in
            markNewSetup()
        }
    }

    private var setupSignature: RunSetupSignature {
        RunSetupSignature(
            question: question,
            scope: scope,
            mode: model.studyWindowMode,
            lastDays: model.lastDays,
            comparisonDays: model.comparisonDays,
            periodStartDate: model.periodStartDate,
            periodEndDate: model.periodEndDate,
            comparisonPrimaryStartDate: model.comparisonPrimaryStartDate,
            comparisonPrimaryEndDate: model.comparisonPrimaryEndDate,
            comparisonBaselineStartDate: model.comparisonBaselineStartDate,
            comparisonBaselineEndDate: model.comparisonBaselineEndDate,
            deploymentComparisonDays: model.deploymentComparisonDays,
            configUpdateDate: model.configUpdateDate,
            configComparisonMode: model.configComparisonMode,
            configBeforeStartDate: model.configBeforeStartDate,
            configBeforeEndDate: model.configBeforeEndDate
        )
    }

    private var activeStep: Int {
        if scopedRuns.contains(where: { [.running, .estimating].contains($0.state) }) {
            return 4
        }
        if scopedCompletedPrompt != nil {
            return 5
        }
        if !hasRunnableScope {
            return 2
        }
        if !hasValidPeriod {
            return 3
        }
        return 4
    }

    private var completedSteps: Set<Int> {
        var steps: Set<Int> = [1]
        if hasRunnableScope {
            steps.insert(2)
        }
        if hasRunnableScope && hasValidPeriod {
            steps.insert(3)
        }
        if scopedCompletedPrompt != nil || scopedRuns.contains(where: { [.succeeded, .partial].contains($0.state) }) {
            steps.insert(4)
        }
        return steps
    }

    private var hasRunnableScope: Bool {
        switch scope {
        case .currentProject:
            return !model.selectedProjectDevices.isEmpty
        case .selectedDevices:
            return !model.selectedIMEIs.isEmpty
        case .savedGroup:
            return model.selectedTestGroup?.deviceIMEIs.isEmpty == false
        }
    }

    private var hasValidPeriod: Bool {
        switch model.studyWindowMode {
        case .sinceDeployment, .comparePrePostDeployment:
            return hasRunnableScope
        default:
            return (try? model.currentStudyMode()) != nil
        }
    }

    private var scopedRuns: [AnalysisRun] {
        runsMatching(scope: scope, model: model)
    }

    private var scopedCompletedPrompt: AnalysisRun? {
        guard let run = model.completedRunPrompt,
              runMatches(scope: scope, model: model, run: run)
        else {
            return nil
        }
        return run
    }

    private func markNewSetup() {
        showLatestStatus = false
        model.dismissCompletedRunPrompt()
    }

    private func consumeRequestedRunSetupReset() {
        guard model.requestedRunSetupReset != nil else { return }
        showLatestStatus = false
        model.dismissCompletedRunPrompt()
        model.requestedRunSetupReset = nil
    }

    private func applyRequestedRunScopeIfNeeded() {
        guard let requestedScope = model.requestedRunScope else { return }
        showLatestStatus = false
        switch requestedScope {
        case .currentProject:
            scope = .currentProject
            question = .fleetHealth
        case .selectedDevices:
            scope = .selectedDevices
            question = .selectedUnits
        case .savedGroup:
            scope = .savedGroup
            question = .selectedUnits
        }
        model.studyWindowMode = question.studyMode
        model.requestedRunScope = nil
    }
}

private struct RunSetupSignature: Equatable {
    let question: RunQuestion
    let scope: RunScope
    let mode: StudyWindowMode
    let lastDays: Int
    let comparisonDays: Int
    let periodStartDate: Date
    let periodEndDate: Date
    let comparisonPrimaryStartDate: Date
    let comparisonPrimaryEndDate: Date
    let comparisonBaselineStartDate: Date
    let comparisonBaselineEndDate: Date
    let deploymentComparisonDays: Int
    let configUpdateDate: Date
    let configComparisonMode: ConfigComparisonMode
    let configBeforeStartDate: Date
    let configBeforeEndDate: Date
}

private enum RunQuestion: String, CaseIterable, Identifiable {
    case fleetHealth
    case selectedUnits
    case sinceDeployment
    case compareDeployment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fleetHealth: return "General fleet health"
        case .selectedUnits: return "Investigate selected units"
        case .sinceDeployment: return "After deployment"
        case .compareDeployment: return "Pre/post deployment"
        }
    }

    var detail: String {
        switch self {
        case .fleetHealth:
            return "Default compares recent performance to a reference window. Choose Last X days when you only want a current screening summary."
        case .selectedUnits:
            return "Fetch data for a named group or selected transmitters."
        case .sinceDeployment:
            return "Start each transmitter at its API deployment date/time and read performance after release."
        case .compareDeployment:
            return "Compare each transmitter after deployment against a same-length reference window before deployment."
        }
    }

    var icon: String {
        switch self {
        case .fleetHealth: return "waveform.path.ecg"
        case .selectedUnits: return "scope"
        case .sinceDeployment: return "calendar.badge.clock"
        case .compareDeployment: return "arrow.left.arrow.right"
        }
    }

    var studyMode: StudyWindowMode {
        switch self {
        case .fleetHealth: return .compareLastDaysToPrior
        case .selectedUnits: return .compareLastDaysToPrior
        case .sinceDeployment: return .sinceDeployment
        case .compareDeployment: return .comparePrePostDeployment
        }
    }
}

private enum RunScope: String, CaseIterable, Identifiable {
    case currentProject
    case selectedDevices
    case savedGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentProject: return "Current project"
        case .selectedDevices: return "Selected transmitters"
        case .savedGroup: return "Saved group"
        }
    }
}

private struct FlowStrip: View {
    @Environment(\.colorScheme) private var scheme
    let activeStep: Int
    let completedSteps: Set<Int>

    private let steps = ["Question", "Scope", "Period", "Fetch", "Read"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, title in
                let step = offset + 1
                HStack(spacing: 7) {
                    Text(completedSteps.contains(step) && activeStep != step ? "✓" : "\(step)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(activeStep == step || completedSteps.contains(step) ? .white : CTTColor.fg2(scheme))
                        .frame(width: 22, height: 22)
                        .background(stepColor(step))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(activeStep == step ? CTTColor.ink(scheme) : CTTColor.fg2(scheme))
                }
                if offset < steps.count - 1 {
                    Rectangle()
                        .fill(completedSteps.contains(step) ? CTTColor.accent(scheme) : CTTColor.line(scheme))
                        .frame(width: 26, height: 1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cttCard()
    }

    private func stepColor(_ step: Int) -> Color {
        if activeStep == step {
            return CTTColor.accent(scheme)
        }
        if completedSteps.contains(step) {
            return CTTColor.green(scheme)
        }
        return CTTColor.track(scheme)
    }
}

private struct QuestionPanel: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @Binding var question: RunQuestion
    @Binding var scope: RunScope

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(step: "1", title: "What are you trying to answer?", detail: "This choice sets the default analysis period. You can still edit it before running.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                ForEach(RunQuestion.allCases) { option in
                    Button {
                        question = option
                        model.studyWindowMode = option.studyMode
                        if option == .selectedUnits, model.selectedTestGroup == nil, !model.selectedIMEIs.isEmpty {
                            scope = .selectedDevices
                        }
                    } label: {
                        OptionTile(
                            icon: option.icon,
                            title: option.title,
                            detail: option.detail,
                            isSelected: question == option
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .cttCard(radius: 9)
    }
}

private struct ScopePanel: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @Binding var scope: RunScope

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(step: "2", title: "Scope", detail: "Every run is attached to a saved group, including fleet-health runs created from a project.")

            VStack(spacing: 8) {
                ScopeButton(scope: .currentProject, selected: $scope, count: model.selectedProjectDevices.count, subtitle: model.selectedProject?.name ?? "No project selected")
                ScopeButton(scope: .selectedDevices, selected: $scope, count: model.selectedIMEIs.count, subtitle: model.selectedProjectSummary)
                ScopeButton(scope: .savedGroup, selected: $scope, count: model.selectedTestGroup?.deviceIMEIs.count ?? 0, subtitle: model.selectedTestGroup?.name ?? "No saved group selected")
            }

            if scope == .currentProject, model.selectedProjectId != nil, model.selectedProjectDevices.isEmpty {
                Button {
                    Task { await model.loadDevicesForSelectedProject() }
                } label: {
                    Label("Load devices for this project", systemImage: "antenna.radiowaves.left.and.right")
                }
                .controlSize(.small)
            }

            if scope == .savedGroup, !model.testGroups.isEmpty {
                Picker("Saved group", selection: $model.selectedTestGroupId) {
                    ForEach(model.testGroups) { group in
                        Text("\(group.name) · \(group.deviceIMEIs.count)").tag(Optional(group.id))
                    }
                }
                .labelsHidden()
            }

            Text(scopeReadout)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CTTColor.fg3(scheme))
                .lineLimit(2)
        }
        .padding(14)
        .cttCard(radius: 9)
        .task(id: model.selectedProjectId) {
            await loadCurrentProjectDevicesIfNeeded()
        }
        .task(id: scope) {
            await loadCurrentProjectDevicesIfNeeded()
        }
    }

    private func loadCurrentProjectDevicesIfNeeded() async {
        guard scope == .currentProject,
              model.selectedProjectId != nil,
              model.selectedProjectDevices.isEmpty,
              !model.isLoading
        else {
            return
        }
        await model.loadDevicesForSelectedProject()
    }

    private var scopeReadout: String {
        switch scope {
        case .currentProject:
            return "\(model.selectedProjectDevices.count) transmitters from \(model.selectedProject?.name ?? "no project")"
        case .selectedDevices:
            return "\(model.selectedIMEIs.count) selected transmitters across \(model.selectedProjectSummary)"
        case .savedGroup:
            return model.selectedTestGroup.map { "\($0.deviceIMEIs.count) transmitters in \($0.name)" } ?? "Choose a saved group"
        }
    }
}

private struct WindowPanel: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @Binding var question: RunQuestion
    let scope: RunScope

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(step: "3", title: "Data period", detail: "Results always state these windows. Comparison windows are validated so they do not overlap.")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                ForEach(StudyWindowMode.allCases) { mode in
                    Button {
                        model.studyWindowMode = mode
                        if mode == .comparePeriods {
                            model.repairComparisonPeriodBoundary()
                        }
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 12, weight: model.studyWindowMode == mode ? .bold : .medium))
                            .foregroundStyle(model.studyWindowMode == mode ? .white : CTTColor.fg2(scheme))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(model.studyWindowMode == mode ? CTTColor.accent(scheme) : CTTColor.paper(scheme))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke(CTTColor.line2(scheme), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            periodControls

            DataWindowsReadout(scope: scope)
        }
        .padding(14)
        .cttCard(radius: 9)
        .onChange(of: question) { _, value in
            model.studyWindowMode = value.studyMode
            if value.studyMode == .comparePeriods {
                model.repairComparisonPeriodBoundary()
            }
        }
    }

    @ViewBuilder
    private var periodControls: some View {
        switch model.studyWindowMode {
        case .allData:
            HStack(spacing: 6) {
                Label("All available telemetry", systemImage: "tray.full")
                    .font(CTTFont.ui(13, weight: .semibold))
                    .foregroundStyle(CTTColor.fg2(scheme))
                InfoPopoverButton(
                    title: "All available telemetry",
                    message: "The app pulls the full telemetry range exposed by the API for the selected transmitters. Use this when you want a broad health review instead of a bounded date window."
                )
            }
        case .specificPeriod:
            DatePairFields(startTitle: "Start", start: $model.periodStartDate, endTitle: "End", end: $model.periodEndDate)
        case .lastDays:
            Stepper("Days: \(model.lastDays)", value: $model.lastDays, in: 1...730)
        case .comparePeriods:
            VStack(alignment: .leading, spacing: 8) {
                Text("Primary period").font(.system(size: 13, weight: .semibold))
                DatePairFields(startTitle: "Primary start", start: $model.comparisonPrimaryStartDate, endTitle: "Primary end", end: $model.comparisonPrimaryEndDate)
                Text("Comparison period").font(.system(size: 13, weight: .semibold))
                DatePairFields(startTitle: "Comparison start", start: $model.comparisonBaselineStartDate, endTitle: "Comparison end", end: $model.comparisonBaselineEndDate)
            }
        case .compareLastDaysToPrior:
            Stepper("Days per period: \(model.comparisonDays)", value: $model.comparisonDays, in: 1...365)
        case .sinceDeployment:
            DeploymentDateReadout(scope: scope)
        case .comparePrePostDeployment:
            DeploymentComparisonControls(scope: scope)
        case .sinceConfigUpdate:
            ConfigComparisonControls()
        }
    }
}

private struct DeploymentComparisonControls: View {
    @EnvironmentObject private var model: AppModel
    let scope: RunScope

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DeploymentDateReadout(scope: scope)
            Stepper("Days before and after: \(model.deploymentComparisonDays)", value: $model.deploymentComparisonDays, in: 1...365)
        }
    }
}

private struct DeploymentDateReadout: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let scope: RunScope

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("API deployment dates")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(CTTColor.accent(scheme))
                        .textCase(.uppercase)
                    InfoPopoverButton(
                        title: "API deployment dates",
                        message: "Deployment dates come from the transmitter deployment fields in the web portal/API. Shipped-at dates are not used here because each transmitter can be deployed at a different time.",
                        width: 350
                    )
                }
                Text(readout)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .lineLimit(2)
            }

            Spacer()

            if scope == .currentProject, model.selectedProjectId != nil, model.selectedProjectDevices.isEmpty {
                Button {
                    Task { await model.loadDevicesForSelectedProject() }
                } label: {
                    Label("Load Devices", systemImage: "antenna.radiowaves.left.and.right")
                }
                .controlSize(.small)
                .disabled(model.isLoading)
            }
        }
        .padding(10)
        .background(CTTColor.accentSoft(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var readout: String {
        let readiness = model.deploymentReadiness(for: scopedIMEIs)
        guard readiness.hasDevices else {
            return "Load or select transmitters first."
        }
        if readiness.isComplete {
            return "Ready: \(readiness.loadedCount)/\(readiness.totalCount) transmitters have deployment timestamps."
        }
        return "\(readiness.loadedCount)/\(readiness.totalCount) cached. Start analysis will query missing transmitter details."
    }

    private var scopedIMEIs: [String] {
        switch scope {
        case .currentProject:
            return model.selectedProjectDevices.map(\.imei)
        case .selectedDevices:
            return Array(model.selectedIMEIs)
        case .savedGroup:
            return model.selectedTestGroup?.deviceIMEIs ?? []
        }
    }
}

private struct ConfigComparisonControls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Config update", selection: $model.configUpdateDate, displayedComponents: [.date, .hourAndMinute])
                .frame(maxWidth: 460)
            Picker("Before period", selection: $model.configComparisonMode) {
                ForEach(ConfigComparisonMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(maxWidth: 460)

            if model.configComparisonMode == .customBeforeWindow {
                DatePairFields(startTitle: "Before start", start: $model.configBeforeStartDate, endTitle: "Before end", end: $model.configBeforeEndDate)
            }
        }
    }
}

private struct DatePairFields: View {
    let startTitle: String
    @Binding var start: Date
    let endTitle: String
    @Binding var end: Date

    var body: some View {
        HStack {
            DatePicker(startTitle, selection: $start, displayedComponents: [.date, .hourAndMinute])
            DatePicker(endTitle, selection: $end, displayedComponents: [.date, .hourAndMinute])
        }
    }
}

private struct DataWindowsReadout: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let scope: RunScope

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text("Data that will be used")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.accent(scheme))
                InfoPopoverButton(
                    title: "Data windows",
                    message: "These are the exact windows the run will pull and analyze. Current windows are the evidence period; reference windows are the comparison period when the selected mode has one.",
                    bullets: [
                        "Comparison windows must not overlap.",
                        "Deployment modes use each transmitter's own API deployment timestamp.",
                        "Devices and Reports repeat these windows so results can be audited."
                    ],
                    width: 360
                )
            }

            if requiresDeploymentDate {
                Text(deploymentWindowDescription)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let mode = try? model.currentStudyMode() {
                ForEach(mode.windows()) { window in
                    HStack {
                        Text(window.title)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CTTColor.ink(scheme))
                            .frame(width: 170, alignment: .leading)
                        Text("\(Formatters.shortDateTime.string(from: window.startDate)) → \(Formatters.shortDateTime.string(from: window.endDate))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(CTTColor.fg2(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            } else {
                Text("Choose valid, non-overlapping dates.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.vermilion(scheme))
            }
        }
        .padding(11)
        .background(CTTColor.accentSoft(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var requiresDeploymentDate: Bool {
        model.studyWindowMode == .sinceDeployment || model.studyWindowMode == .comparePrePostDeployment
    }

    private var deploymentWindowDescription: String {
        let readiness = model.deploymentReadiness(for: scopedIMEIs)
        switch model.studyWindowMode {
        case .sinceDeployment:
            return "Per transmitter: deployment timestamp → now. \(readiness.statusText)"
        case .comparePrePostDeployment:
            return "Per transmitter: \(model.deploymentComparisonDays)d before deployment vs \(model.deploymentComparisonDays)d after, capped at now. \(readiness.statusText)"
        default:
            return readiness.statusText
        }
    }

    private var scopedIMEIs: [String] {
        switch scope {
        case .currentProject:
            return model.selectedProjectDevices.map(\.imei)
        case .selectedDevices:
            return Array(model.selectedIMEIs)
        case .savedGroup:
            return model.selectedTestGroup?.deviceIMEIs ?? []
        }
    }
}

private struct DataBudgetPanel: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let scope: RunScope
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(step: "4", title: "Fetch budget", detail: "API calls are paced to the service limit. The run itself is measured by transmitters.")

            HStack(spacing: 6) {
                Picker("Retention", selection: $model.retentionMode) {
                    ForEach(RetentionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                InfoPopoverButton(
                    title: "Retention",
                    message: "Retention controls how much pulled telemetry stays on this Mac after analysis.",
                    bullets: [
                        "Metrics plus bounded raw cache keeps the analysis results and a limited local sample for review.",
                        "Full telemetry keeps the pulled raw records locally for deeper audit work.",
                        "The app does not create a cloud runner or sync telemetry off this machine."
                    ],
                    width: 360
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                BudgetMetric(value: "\(estimate.estimatedRequests)", label: "API calls")
                BudgetMetric(value: Formatters.duration(estimate.estimatedMinimumDuration), label: "min time")
                BudgetMetric(value: ByteCountFormatter.string(fromByteCount: estimate.estimatedBytes, countStyle: .file), label: "local size")
                BudgetMetric(value: "\(deviceCount)", label: "transmitters")
            }

            startButton
        }
        .padding(14)
        .cttCard(radius: 9)
        .onAppear { model.updateEstimate() }
        .onChange(of: scope) { _, _ in model.updateEstimate() }
    }

    private var estimate: PullEstimate {
        PullEstimator().estimate(
            deviceCount: deviceCount,
            estimatedPagesPerEndpoint: model.estimatedPagesPerEndpoint,
            diskBudgetBytes: Int64(model.diskBudgetGB * 1_073_741_824),
            retentionMode: model.retentionMode
        )
    }

    private var deviceCount: Int {
        switch scope {
        case .currentProject: return model.selectedProjectDevices.count
        case .selectedDevices: return model.selectedIMEIs.count
        case .savedGroup: return model.selectedTestGroup?.deviceIMEIs.count ?? 0
        }
    }

    @ViewBuilder
    private var startButton: some View {
        Button {
            Task { await startRun() }
        } label: {
            Label("Start analysis", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CTTColor.accent(scheme))
        .disabled(model.isLoading || deviceCount == 0)
    }

    private func startRun() async {
        switch scope {
        case .currentProject:
            onStart()
            await model.runFleetHealthForSelectedProject()
        case .selectedDevices:
            onStart()
            await model.runSelectedDevices()
        case .savedGroup:
            if let group = model.selectedTestGroup {
                onStart()
                await model.runTestGroup(group)
            } else {
                model.presentError("Choose a saved group before starting the analysis.")
            }
        }
    }
}

private struct RunProgressPanel: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let scope: RunScope
    @Binding var showLatestStatus: Bool

    private var scopedRuns: [AnalysisRun] {
        runsMatching(scope: scope, model: model)
    }

    private var inFlightRun: AnalysisRun? {
        scopedRuns.first { [.running, .estimating].contains($0.state) }
    }

    private var visibleRun: AnalysisRun? {
        if let inFlightRun {
            return inFlightRun
        }
        guard showLatestStatus else {
            return nil
        }
        return scopedRuns.first
    }

    private var transmitterCount: Int {
        switch scope {
        case .currentProject:
            return model.selectedProjectDevices.count
        case .selectedDevices:
            return model.selectedIMEIs.count
        case .savedGroup:
            return model.selectedTestGroup?.deviceIMEIs.count ?? 0
        }
    }

    private var currentDataPeriodLabel: String {
        if model.studyWindowMode == .sinceDeployment {
            return "Per transmitter: API deployment timestamp → now."
        }
        if model.studyWindowMode == .comparePrePostDeployment {
            return "Per transmitter: \(model.deploymentComparisonDays) days before deployment vs \(model.deploymentComparisonDays) days after deployment."
        }
        if let mode = try? model.currentStudyMode() {
            return mode.displayName
        }
        return "Choose valid dates before starting."
    }

    private var latestRunExists: Bool {
        let scopedRuns = runsMatching(scope: scope, model: model)
        return !scopedRuns.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(step: "5", title: "Analysis status", detail: "When a run finishes, Devices reads the selected completed run. Changing scope or period starts a new setup.")

            if let activeRun = visibleRun {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 6) {
                        Text(activeRun.state.displayName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(statusColor(activeRun.state))
                        InfoPopoverButton(
                            title: "Analysis status",
                            message: statusExplanation(for: activeRun),
                            bullets: [
                                "Green transmitters completed.",
                                "Ochre transmitters are running or in progress.",
                                "Red transmitters failed and need retry or inspection.",
                                "Gray transmitters are queued."
                            ],
                            width: 380
                        )
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(finishedTransmitters(in: activeRun)) / \(totalTransmitters(in: activeRun)) transmitters checked")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(CTTColor.fg2(scheme))
                        Text("\(activeRun.progress.completedRequests) / \(max(activeRun.progress.estimatedRequests, 1)) API calls")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(CTTColor.fg3(scheme))
                    }
                }

                ProgressView(value: activeRun.progress.fractionComplete)
                    .tint(CTTColor.accent(scheme))

                DeviceCompletionGrid(results: activeRun.progress.deviceResults)

                RunStatusLegend()

                Text("Data source: \(runDisplayName(activeRun)) · \(runDataUsedLabel(activeRun))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(2)

                if inFlightRun == nil {
                    Button {
                        showLatestStatus = false
                        model.dismissCompletedRunPrompt()
                    } label: {
                        Label("Set up a new run", systemImage: "plus")
                    }
                    .controlSize(.small)
                }
            } else if latestRunExists {
                ReadyForNewRunState(
                    transmitterCount: transmitterCount,
                    dataPeriod: currentDataPeriodLabel,
                    latestRunSummary: "Previous matching runs remain in history below. Start analysis to pull fresh data for this setup."
                )
            } else {
                ReadyForNewRunState(
                    transmitterCount: transmitterCount,
                    dataPeriod: currentDataPeriodLabel,
                    latestRunSummary: "No run exists for this scope yet."
                )
            }
        }
        .padding(14)
        .cttCard(radius: 9)
    }

    private func totalTransmitters(in run: AnalysisRun) -> Int {
        max(run.selectedIMEIs.count, run.progress.deviceResults.count)
    }

    private func finishedTransmitters(in run: AnalysisRun) -> Int {
        let finished = run.progress.deviceResults.filter { $0.state.isTerminal }.count
        if finished == 0, [.succeeded, .partial, .failed, .canceled].contains(run.state) {
            return totalTransmitters(in: run)
        }
        return finished
    }

    private func statusExplanation(for run: AnalysisRun) -> String {
        let results = run.progress.deviceResults
        let succeeded = results.filter { $0.state == .succeeded }.count
        let failed = results.filter { $0.state == .failed }.count
        let skipped = results.filter { $0.state == .skipped }.count
        let total = totalTransmitters(in: run)

        switch run.state {
        case .pending:
            return "Pending means the run has been saved but has not started pulling telemetry."
        case .estimating:
            return "Estimating means the app is calculating the API work before pulling transmitter data."
        case .running:
            return "Running means telemetry is being pulled now. Green transmitters have completed; ochre transmitters are in progress; gray transmitters are queued."
        case .succeeded:
            return "Succeeded means every selected transmitter produced usable pulled data."
        case .partial:
            return "Partial results means the run finished with mixed outcomes: \(succeeded) of \(total) transmitters produced usable data, \(failed) failed\(skipped > 0 ? ", and \(skipped) were skipped" : ""). Devices and Reports use completed transmitters; red entries show units to retry or inspect."
        case .failed:
            return "Failed means no selected transmitter produced usable data for this pull. Check the red transmitter tooltips and run history before retrying."
        case .canceled:
            return "Canceled means the run was stopped before all selected transmitters finished."
        }
    }

    private func statusColor(_ state: RunState) -> Color {
        switch state {
        case .succeeded: return CTTColor.green(scheme)
        case .partial, .running, .estimating: return CTTColor.ochre(scheme)
        case .failed, .canceled: return CTTColor.vermilion(scheme)
        case .pending: return CTTColor.fallback(scheme)
        }
    }
}

private struct ReadyForNewRunState: View {
    @Environment(\.colorScheme) private var scheme
    let transmitterCount: Int
    let dataPeriod: String
    let latestRunSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(CTTColor.accent(scheme))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ready for new analysis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CTTColor.ink(scheme))
                    HStack(spacing: 5) {
                        Text("Start analysis to pull telemetry for the current setup.")
                            .font(.system(size: 12))
                            .foregroundStyle(CTTColor.fg2(scheme))
                        InfoPopoverButton(
                            title: "Starting a new run",
                            message: "Changing question, scope, or data period does not reuse the old analysis. Start analysis creates a new run with the currently shown setup."
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                ReadyRunFact(value: "\(transmitterCount)", label: "transmitters")
                    .frame(width: 142)
                ReadyRunFact(value: dataPeriod, label: "data period", isLongValue: true)
            }

            HStack(alignment: .top, spacing: 5) {
                Text(latestRunSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                InfoPopoverButton(
                    title: "Run history",
                    message: "Previous runs remain below for audit and deletion. The setup panel stays ready for a fresh pull with the current choices."
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReadyRunFact: View {
    @Environment(\.colorScheme) private var scheme
    let value: String
    let label: String
    var isLongValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: isLongValue ? 13 : 20, weight: .bold, design: .monospaced))
                .foregroundStyle(CTTColor.ink(scheme))
                .lineLimit(isLongValue ? 2 : 1)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CTTColor.fg3(scheme))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(CTTColor.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RunStatusLegend: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            LegendSwatch(color: CTTColor.green(scheme), title: "complete", help: DevicePullState.succeeded.definition)
            LegendSwatch(color: CTTColor.ochre(scheme), title: "running", help: DevicePullState.running.definition)
            LegendSwatch(color: CTTColor.vermilion(scheme), title: "failed", help: DevicePullState.failed.definition)
            LegendSwatch(color: CTTColor.track(scheme), title: "queued", help: DevicePullState.pending.definition)
            LegendSwatch(color: CTTColor.fallback(scheme), title: "skipped", help: DevicePullState.skipped.definition)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(CTTColor.fg3(scheme))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LegendSwatch: View {
    let color: Color
    let title: String
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
        }
        .help(help)
    }
}

private struct CompletedRunCallout: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let run: AnalysisRun

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CTTColor.green(scheme))

            VStack(alignment: .leading, spacing: 4) {
                Text("Analysis complete")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                Text("\(run.selectedIMEIs.count) transmitters checked. Open Devices to review the ranked transmitter results for this run.")
                    .font(.system(size: 12))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .lineLimit(2)
            }

            Spacer()

            Button {
                model.dismissCompletedRunPrompt()
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
            .controlSize(.small)

            Button {
                model.openResults(for: run)
            } label: {
                Label("Open Results", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.borderedProminent)
            .tint(CTTColor.accent(scheme))
            .controlSize(.small)
        }
        .padding(14)
        .background(CTTColor.accentSoft(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(CTTColor.accent(scheme), lineWidth: 1)
        }
    }
}

private struct RunHistoryPanel: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let scope: RunScope

    private var scopedRuns: [AnalysisRun] {
        runsMatching(scope: scope, model: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PanelTitle(step: nil, title: historyTitle, detail: "These runs match the selected scope. Use Devices for completed run results or delete runs that are no longer useful.")
                Spacer()
                Text("\(scopedRuns.count) runs")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
            }

            if scopedRuns.isEmpty {
                ContentUnavailableView("No runs for this scope", systemImage: "play.rectangle", description: Text("Start analysis to create device summaries, reports, and alerts for this selection."))
                    .frame(minHeight: 120)
            } else {
                ForEach(scopedRuns.prefix(8)) { run in
                    RunHistoryRow(run: run)
                }
            }
        }
        .padding(14)
        .cttCard(radius: 9)
    }

    private var historyTitle: String {
        switch scope {
        case .currentProject:
            return "Runs for current project"
        case .selectedDevices:
            return "Runs for selected transmitters"
        case .savedGroup:
            return "Runs for saved group"
        }
    }
}

private struct RunHistoryRow: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let run: AnalysisRun

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(statusColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(runDisplayName(run))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CTTColor.ink(scheme))
                        .lineLimit(1)
                    Spacer()
                    Text(run.state.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }

                Text("\(run.selectedIMEIs.count) transmitters · \(run.analysisMode?.displayName ?? "selected period")")
                    .font(.system(size: 12))
                    .foregroundStyle(CTTColor.fg2(scheme))
                Text("Data used: \(runDataUsedLabel(run))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
            }

            VStack(spacing: 6) {
                if hasDeviceResults {
                    Button {
                        model.openResults(for: run)
                    } label: {
                        Label("Open Devices", systemImage: "waveform.path.ecg")
                    }
                    .controlSize(.small)
                } else {
                    Label("No Results", systemImage: "waveform.path.ecg")
                        .font(.system(size: 12))
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .labelStyle(.titleAndIcon)
                }

                Button(role: .destructive) {
                    model.deleteRun(run)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
        .padding(11)
        .background(CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }

    private var statusColor: Color {
        switch run.state {
        case .succeeded: return CTTColor.green(scheme)
        case .partial, .running, .estimating: return CTTColor.ochre(scheme)
        case .failed, .canceled: return CTTColor.vermilion(scheme)
        case .pending: return CTTColor.fallback(scheme)
        }
    }

    private var hasDeviceResults: Bool {
        [.succeeded, .partial].contains(run.state) && run.deviceSummaries?.isEmpty == false
    }
}

@MainActor
private func runsMatching(scope: RunScope, model: AppModel) -> [AnalysisRun] {
    model.runs.filter { runMatches(scope: scope, model: model, run: $0) }
}

@MainActor
private func runMatches(scope: RunScope, model: AppModel, run: AnalysisRun) -> Bool {
    switch scope {
    case .currentProject:
        guard let projectId = model.selectedProjectId else { return false }
        let projectIds = Set([projectId])
        let currentProjectIMEIs = Set(model.selectedProjectDevices.map(\.imei))
        guard Set(run.selectedProjectIds) == projectIds else { return false }
        guard !currentProjectIMEIs.isEmpty else { return true }
        return Set(run.selectedIMEIs) == currentProjectIMEIs
    case .selectedDevices:
        let selectedIMEIs = model.selectedIMEIs
        guard !selectedIMEIs.isEmpty else { return false }
        let selectedProjectIds = Set(model.selectedIMEIProjectIds)
        return Set(run.selectedIMEIs) == selectedIMEIs
            && (selectedProjectIds.isEmpty || Set(run.selectedProjectIds) == selectedProjectIds)
    case .savedGroup:
        guard let group = model.selectedTestGroup else { return false }
        return run.testGroupId == group.id
            || (Set(run.selectedProjectIds) == Set(group.projectIds)
                && Set(run.selectedIMEIs) == Set(group.deviceIMEIs))
    }
}

private func runDisplayName(_ run: AnalysisRun) -> String {
    if run.name.hasPrefix("Pull ") {
        return "Analysis \(run.name.dropFirst("Pull ".count))"
    }
    if run.name.hasPrefix("Investigation ") {
        return "Analysis \(run.name.dropFirst("Investigation ".count))"
    }
    return run.name
}

private func runDataUsedLabel(_ run: AnalysisRun) -> String {
    guard let mode = run.analysisMode else {
        return "\(Formatters.shortDateTime.string(from: run.startDate)) → \(Formatters.shortDateTime.string(from: run.endDate))"
    }
    if mode.usesPerDeviceDeploymentWindows {
        return "\(mode.displayName) · per-device deployment windows · pull range \(Formatters.shortDateTime.string(from: run.startDate)) → \(Formatters.shortDateTime.string(from: run.endDate))"
    }
    return "\(mode.displayName) · \(Formatters.shortDateTime.string(from: run.startDate)) → \(Formatters.shortDateTime.string(from: run.endDate))"
}

private extension AnalysisStudyMode {
    var usesPerDeviceDeploymentWindows: Bool {
        switch self {
        case .sinceDeviceDeployments, .compareDeviceDeploymentWindows:
            return true
        default:
            return false
        }
    }
}

private struct ScopeButton: View {
    @Environment(\.colorScheme) private var scheme
    let scope: RunScope
    @Binding var selected: RunScope
    let count: Int
    let subtitle: String

    var body: some View {
        Button {
            selected = scope
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(scope.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CTTColor.ink(scheme))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .lineLimit(1)
                }
                Spacer()
                Text("\(count)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected == scope ? CTTColor.accent(scheme) : CTTColor.fg2(scheme))
            }
            .padding(10)
            .background(selected == scope ? CTTColor.accentSoft(scheme) : CTTColor.paper(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected == scope ? CTTColor.accent(scheme) : CTTColor.line2(scheme), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct OptionTile: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                InfoPopoverButton(title: title, message: detail)
                if isSelected {
                    Text("selected")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(isSelected ? CTTColor.accent(scheme) : CTTColor.fg2(scheme))

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CTTColor.ink(scheme))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(isSelected ? CTTColor.accentSoft(scheme) : CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? CTTColor.accent(scheme) : CTTColor.line2(scheme), lineWidth: isSelected ? 1.5 : 1)
        }
    }
}

private struct PanelTitle: View {
    @Environment(\.colorScheme) private var scheme
    let step: String?
    let title: String
    let detail: String

    init(step: String?, title: String, detail: String) {
        self.step = step
        self.title = title
        self.detail = detail
    }

    init(step: String, title: String, detail: String) {
        self.step = step
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let step {
                    Text("\(step) ·")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(CTTColor.accent(scheme))
                }
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                if !detail.isEmpty {
                    InfoPopoverButton(title: title, message: detail)
                }
            }
        }
    }
}

private struct BudgetMetric: View {
    @Environment(\.colorScheme) private var scheme
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(CTTColor.ink(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(CTTColor.fg3(scheme))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CTTColor.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DeviceCompletionGrid: View {
    @Environment(\.colorScheme) private var scheme
    let results: [DevicePullResult]

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(13), spacing: 4), count: 18)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(results.isEmpty ? placeholderResults : results) { result in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: result.state))
                    .frame(width: 13, height: 13)
                    .help(result.helpText)
            }
        }
    }

    private var placeholderResults: [DevicePullResult] {
        (0..<36).map { index in
            DevicePullResult(imei: "queued-\(index)", state: .pending, retryCount: 0, message: nil)
        }
    }

    private func color(for state: DevicePullState) -> Color {
        switch state {
        case .succeeded: return CTTColor.green(scheme)
        case .running: return CTTColor.ochre(scheme)
        case .failed: return CTTColor.vermilion(scheme)
        case .skipped: return CTTColor.fallback(scheme)
        case .pending: return CTTColor.track(scheme)
        }
    }
}

private extension DevicePullResult {
    var helpText: String {
        let prefix = "\(imei): \(state.displayName). \(state.definition)"
        guard let message, !message.isEmpty else {
            return prefix
        }
        return "\(prefix) \(message)"
    }
}

private extension DevicePullState {
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .skipped:
            return true
        case .pending, .running:
            return false
        }
    }

    var displayName: String {
        switch self {
        case .pending: return "Queued"
        case .running: return "Running"
        case .succeeded: return "Complete"
        case .skipped: return "Skipped"
        case .failed: return "Failed"
        }
    }

    var definition: String {
        switch self {
        case .pending:
            return "Queued means the transmitter has not been pulled yet."
        case .running:
            return "Running means this transmitter is currently being pulled or retried."
        case .succeeded:
            return "Complete means the transmitter produced usable telemetry for this run."
        case .skipped:
            return "Skipped means the run deliberately did not pull this transmitter, usually because required setup data was missing."
        case .failed:
            return "Failed means the app could not produce usable pulled data for this transmitter."
        }
    }
}

private extension RunState {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .estimating: return "Estimating"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .partial: return "Partial results"
        case .failed: return "Failed"
        case .canceled: return "Canceled"
        }
    }

    var definition: String {
        switch self {
        case .pending:
            return "Pending means the run has been saved but has not started."
        case .estimating:
            return "Estimating means the app is calculating the pull work."
        case .running:
            return "Running means telemetry is being pulled now."
        case .succeeded:
            return "Succeeded means every selected transmitter produced usable data."
        case .partial:
            return "Partial results mean the run finished with at least one successful transmitter and at least one failed or skipped transmitter."
        case .failed:
            return "Failed means no selected transmitter produced usable data."
        case .canceled:
            return "Canceled means the run was stopped before completion."
        }
    }
}
