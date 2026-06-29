import GSMToolsCore
import MapKit
import SwiftUI

private enum LifelineSortMode: String, CaseIterable, Identifiable {
    case deviation
    case lastConnection
    case alphabetical
    case mostConnections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .deviation: return "Deviation"
        case .lastConnection: return "Last connection"
        case .alphabetical: return "A-Z"
        case .mostConnections: return "Most connections"
        }
    }

    var caption: String {
        switch self {
        case .deviation: return "worst first"
        case .lastConnection: return "last connection"
        case .alphabetical: return "A-Z"
        case .mostConnections: return "most check-ins"
        }
    }

    func sort(_ lhs: DeviceDiagnostic, _ rhs: DeviceDiagnostic) -> Bool {
        switch self {
        case .deviation:
            return lhs < rhs
        case .lastConnection:
            return Self.compareDates(lhs.device.latestConnectionAt, rhs.device.latestConnectionAt) {
                lhs.device.displayName.localizedCaseInsensitiveCompare(rhs.device.displayName) == .orderedAscending
            }
        case .alphabetical:
            let order = lhs.device.displayName.localizedCaseInsensitiveCompare(rhs.device.displayName)
            if order == .orderedSame {
                return lhs.device.imei < rhs.device.imei
            }
            return order == .orderedAscending
        case .mostConnections:
            let lhsCount = lhs.current?.connectionCount ?? 0
            let rhsCount = rhs.current?.connectionCount ?? 0
            if lhsCount == rhsCount {
                return lhs.device.displayName.localizedCaseInsensitiveCompare(rhs.device.displayName) == .orderedAscending
            }
            return lhsCount > rhsCount
        }
    }

    private static func compareDates(_ lhs: String?, _ rhs: String?, tieBreak: () -> Bool) -> Bool {
        let lhsDate = lhs.flatMap { try? TimestampNormalizer.parseISO8601($0) }
        let rhsDate = rhs.flatMap { try? TimestampNormalizer.parseISO8601($0) }
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?):
            if lhsDate == rhsDate { return tieBreak() }
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return tieBreak()
        }
    }
}

private enum LifelineViewport: String, CaseIterable, Identifiable {
    case cohort
    case transmitter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cohort: return "Cohort"
        case .transmitter: return "Transmitter"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .cohort: return "1"
        case .transmitter: return "2"
        }
    }
}

private enum DetailMetric: String, CaseIterable, Identifiable {
    case gpsSuccess
    case fixTime
    case connections
    case solar
    case battery
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gpsSuccess: return "GPS fix yield"
        case .fixTime: return "Fix time"
        case .connections: return "Connections"
        case .solar: return "Solar"
        case .battery: return "Battery"
        case .activity: return "ACC / activity"
        }
    }

    var shortTitle: String {
        switch self {
        case .gpsSuccess: return "GPS"
        case .fixTime: return "Fix"
        case .connections: return "Conn"
        case .solar: return "Solar"
        case .battery: return "Battery"
        case .activity: return "ACC"
        }
    }

    var valueHeader: String {
        switch self {
        case .gpsSuccess, .solar:
            return "%"
        case .fixTime:
            return "TTF"
        case .connections:
            return "check-ins"
        case .battery:
            return "volts"
        case .activity:
            return "activity"
        }
    }

    var systemImage: String {
        switch self {
        case .gpsSuccess: return "location"
        case .fixTime: return "timer"
        case .connections: return "antenna.radiowaves.left.and.right"
        case .solar: return "sun.max"
        case .battery: return "battery.75"
        case .activity: return "waveform.path.ecg"
        }
    }

    var usesFixMap: Bool {
        switch self {
        case .gpsSuccess, .fixTime:
            return true
        case .connections, .solar, .battery, .activity:
            return false
        }
    }

    var usesTimelineBand: Bool {
        switch self {
        case .gpsSuccess, .fixTime, .connections:
            return true
        case .solar, .battery, .activity:
            return false
        }
    }

    var lowerIsBetter: Bool {
        switch self {
        case .fixTime:
            return true
        case .gpsSuccess, .connections, .solar, .battery, .activity:
            return false
        }
    }

    func formatRawValue(_ value: Double) -> String {
        switch self {
        case .gpsSuccess, .solar:
            return "\(Int((value * 100).rounded()))%"
        case .fixTime:
            return value >= 60 ? "\(Int(value.rounded()))s" : "\(Int(value.rounded()))s"
        case .connections:
            return "\(Int(value.rounded()))"
        case .battery:
            return String(format: "%.2fV", value)
        case .activity:
            return value >= 100 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
        }
    }
}

struct LifelineWorkspaceView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @State private var selectedIMEI: String?
    @State private var searchText = ""
    @State private var sortMode: LifelineSortMode = .deviation
    @State private var cohortMetric: DetailMetric = .gpsSuccess
    @State private var viewport: LifelineViewport = .cohort

    private var allDevices: [DeviceDiagnostic] {
        let summaries = model.latestLifelineSummariesByIMEI
        let run = model.latestLifelineRun

        let diagnostics = model.lifelineDevices
            .map { device in
                DeviceDiagnostic(device: device, analysis: summaries[device.imei], run: run)
            }

        return diagnostics.sorted(by: sortMode.sort)
    }

    private var filteredDevices: [DeviceDiagnostic] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? allDevices : allDevices.filter { diagnostic in
            diagnostic.device.displayName.localizedCaseInsensitiveContains(query)
                || diagnostic.device.imei.localizedCaseInsensitiveContains(query)
                || diagnostic.device.deviceType.localizedCaseInsensitiveContains(query)
        }

        return filtered
    }

    private var selectedDevice: DeviceDiagnostic? {
        filteredDevices.first { $0.id == selectedIMEI }
            ?? allDevices.first { $0.id == selectedIMEI }
            ?? filteredDevices.first
            ?? allDevices.first
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceToolbar(
                sortMode: $sortMode,
                selectedRunId: $model.selectedLifelineRunId,
                viewport: $viewport
            )

            if model.lifelineDevices.isEmpty {
                EmptyLifelineState()
            } else {
                workspaceBody
            }
        }
        .background(CTTColor.canvas(scheme))
        .task(id: model.selectedProjectId) {
            guard model.selectedProjectId != nil, model.selectedProjectDevices.isEmpty else { return }
            await model.loadDevicesForSelectedProject()
        }
        .onAppear {
            selectedIMEI = selectedIMEI ?? allDevices.first?.id
            applyRequestedFocus()
        }
        .onChange(of: allDevices.map(\.id)) { _, ids in
            if selectedIMEI.map({ ids.contains($0) }) != true {
                selectedIMEI = ids.first
            }
            applyRequestedFocus()
        }
        .onChange(of: filteredDevices.map(\.id)) { _, ids in
            guard viewport == .transmitter, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if selectedIMEI.map({ ids.contains($0) }) != true {
                selectedIMEI = ids.first
            }
        }
        .onChange(of: model.lifelineRunOptions.map(\.id)) { _, ids in
            if let selectedRunId = model.selectedLifelineRunId, !ids.contains(selectedRunId) {
                model.selectedLifelineRunId = nil
            }
        }
        .onChange(of: model.requestedLifelineIMEI) { _, _ in
            applyRequestedFocus()
        }
    }

    private func applyRequestedFocus() {
        guard let requestedIMEI = model.requestedLifelineIMEI,
              allDevices.contains(where: { $0.id == requestedIMEI })
        else {
            return
        }
        selectedIMEI = requestedIMEI
        viewport = .transmitter
        model.requestedLifelineIMEI = nil
    }

    @ViewBuilder
    private var workspaceBody: some View {
        switch viewport {
        case .cohort:
            CohortTimelinePanel(
                devices: allDevices,
                selectedMetric: $cohortMetric,
                selectedIMEI: $selectedIMEI,
                openSelected: { viewport = .transmitter }
            )
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .transmitter:
            HSplitView {
                DeviceLifelineList(
                    devices: filteredDevices,
                    totalDeviceCount: model.lifelineDevices.count,
                    searchText: $searchText,
                    sortMode: sortMode,
                    selectedIMEI: $selectedIMEI
                )
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 430)

                if let selectedDevice {
                    LifelineDetail(device: selectedDevice, selectedMetric: $cohortMetric)
                        .frame(minWidth: 720)
                } else {
                    ContentUnavailableView("No matching transmitters", systemImage: "magnifyingglass", description: Text("Search by alias, IMEI, or transmitter type."))
                        .frame(minWidth: 620)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WorkspaceToolbar: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @Binding var sortMode: LifelineSortMode
    @Binding var selectedRunId: UUID?
    @Binding var viewport: LifelineViewport

    var body: some View {
        HStack(spacing: 10) {
            Text(context)
                .font(CTTFont.mono(12))
                .foregroundStyle(CTTColor.fg2(scheme))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            ViewportSwitch(selection: $viewport)
                .frame(width: 230)

            Picker("Analysis source", selection: $selectedRunId) {
                Text("Latest matching run").tag(UUID?.none)
                ForEach(model.lifelineRunOptions) { run in
                    Text(runSourceLabel(run)).tag(Optional(run.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 240)
            .disabled(model.lifelineRunOptions.isEmpty)

            if viewport == .transmitter {
                Picker("Sort", selection: $sortMode) {
                    ForEach(LifelineSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(CTTColor.titlebar(scheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CTTColor.line(scheme))
                .frame(height: 1)
        }
    }

    private var context: String {
        let project = model.selectedProject?.name ?? "No project selected"
        let scope = model.selectedIMEIs.isEmpty ? "project fleet" : "\(model.lifelineDevices.count) selected units"
        if let run = model.activeLifelineRun {
            let study = run.analysisMode?.displayName ?? "selected period"
            return "\(project) · \(scope) · \(study) · \(Formatters.shortDateTime.string(from: run.updatedAt))"
        }
        return "\(project) · \(scope) · no completed analysis run for this scope yet"
    }

    private func runSourceLabel(_ run: AnalysisRun) -> String {
        "\(normalizedRunName(run)) · \(Formatters.shortDateTime.string(from: run.updatedAt))"
    }

    private func normalizedRunName(_ run: AnalysisRun) -> String {
        if run.name.hasPrefix("Pull ") {
            return "Analysis \(run.name.dropFirst("Pull ".count))"
        }
        if run.name.hasPrefix("Investigation ") {
            return "Analysis \(run.name.dropFirst("Investigation ".count))"
        }
        return run.name
    }
}

private struct ViewportSwitch: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: LifelineViewport

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LifelineViewport.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Text(option.title)
                        .font(CTTFont.ui(12, weight: selection == option ? .bold : .semibold))
                        .foregroundStyle(selection == option ? .white : CTTColor.fg2(scheme))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(selection == option ? CTTColor.accent(scheme) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(option.shortcutKey, modifiers: [.command, .option])
                .accessibilityLabel(option.title)
            }
        }
        .padding(2)
        .background(CTTColor.track(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct EmptyLifelineState: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(CTTColor.fg3(scheme))

            Text(emptyTitle)
                .font(CTTFont.display(24, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))

            Text(emptyMessage)
                .font(CTTFont.ui(13, weight: .medium))
                .foregroundStyle(CTTColor.fg2(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if model.selectedProjectId != nil {
                Button {
                    Task { await model.loadDevicesForSelectedProject() }
                } label: {
                    Label("Load Devices", systemImage: "antenna.radiowaves.left.and.right")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CTTColor.canvas(scheme))
    }

    private var emptyTitle: String {
        model.projects.isEmpty ? "No telemetry workspace yet" : "No devices loaded"
    }

    private var emptyMessage: String {
        if model.projects.isEmpty {
            return "Refresh the account or add an API key in Settings. The lifeline workspace needs project devices before it can rank deviations."
        }
        return "Load devices for the selected project to build the lifeline-ranked triage list."
    }
}

private struct CohortTimelinePanel: View {
    @Environment(\.colorScheme) private var scheme
    let devices: [DeviceDiagnostic]
    @Binding var selectedMetric: DetailMetric
    @Binding var selectedIMEI: String?
    let openSelected: () -> Void

    private var rankedDevices: [DeviceDiagnostic] {
        devices.sorted { lhs, rhs in
            lhs.metricSortValue(for: selectedMetric) < rhs.metricSortValue(for: selectedMetric)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            metricBar
            timelineHeader

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rankedDevices) { device in
                        CohortTimelineRow(
                            device: device,
                            metric: selectedMetric,
                            isSelected: selectedIMEI == device.id
                        )
                        .onTapGesture {
                            selectedIMEI = device.id
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cttCard(radius: 9)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Cohort timeline")
                .font(CTTFont.display(22, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))
            InfoPopoverButton(
                title: "Cohort timeline",
                message: "Each row is one transmitter for the selected metric. Time-based metrics show discrete buckets. Summary metrics show a normalized value scale, not a date timeline.",
                bullets: [
                    "Rows rank worst first by change vs reference, or by absolute current screening value when no reference exists.",
                    "GPS/Fixed/Connections: each mark is a bucket in the pulled time window; hover or click a mark for the bucket counts.",
                    "Solar/Battery/ACC: the center bar is a value scale only. The date range is still the run window, but the bar endpoint is not the last observation time.",
                    "Within threshold means no V0 screen was crossed; it does not prove the transmitter or animal is fine."
                ],
                width: 390
            )
            Text(hasComparison ? "multi-unit comparison · current vs reference" : "multi-unit current screen")
                .font(CTTFont.ui(12, weight: .semibold))
                .foregroundStyle(CTTColor.fg3(scheme))
            Spacer()
            Text(selectedMetric.title)
                .font(CTTFont.mono(12, weight: .bold))
                .foregroundStyle(CTTColor.accent(scheme))
                .lineLimit(1)
            Text("\(devices.count) transmitters")
                .font(CTTFont.mono(12, weight: .bold))
                .foregroundStyle(CTTColor.fg2(scheme))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CTTColor.paper(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
        }
    }

    private var metricBar: some View {
        HStack(spacing: 10) {
            Text("Metric")
                .font(CTTFont.label(11))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.fg3(scheme))
            InfoPopoverButton(
                title: "Metric thresholds",
                message: "These are screening thresholds for triage, not final statistical claims.",
                bullets: [
                    "GPS marks review at a 10% relative drop and flags at 25%.",
                    "Fix time marks review at 25% slower and flags at 50% slower.",
                    "Check-ins mark review at 25% fewer and flag at 50% fewer.",
                    "Without a reference, absolute screening thresholds apply."
                ],
                width: 390
            )

            HStack(spacing: 0) {
                ForEach(DetailMetric.allCases) { metric in
                    Button {
                        selectedMetric = metric
                    } label: {
                        Text(metric.shortTitle)
                            .font(CTTFont.ui(12, weight: selectedMetric == metric ? .bold : .semibold))
                            .foregroundStyle(selectedMetric == metric ? .white : CTTColor.fg2(scheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 11)
                            .frame(height: 29)
                            .background(selectedMetric == metric ? CTTColor.accent(scheme) : CTTColor.paper(scheme))
                    }
                    .buttonStyle(.plain)
                    .help("Rank cohort by \(metric.title)")

                    if metric != DetailMetric.allCases.last {
                        Rectangle()
                            .fill(CTTColor.line2(scheme))
                            .frame(width: 1, height: 29)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CTTColor.line2(scheme), lineWidth: 1)
            }

            Spacer()

            HStack(spacing: 6) {
                Text(hasComparison ? "vs reference" : "current period")
                    .font(CTTFont.mono(11, weight: .bold))
                    .foregroundStyle(hasComparison ? CTTColor.accent(scheme) : CTTColor.fg2(scheme))
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(hasComparison ? CTTColor.accentSoft(scheme) : CTTColor.paper(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("ranked by \(selectedMetric.title.lowercased())")
                    .font(CTTFont.mono(12, weight: .bold))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CTTColor.panel(scheme))
    }

    private var timelineHeader: some View {
        HStack {
            Text("transmitter · status")
                .frame(width: 230, alignment: .leading)
            HStack {
                if selectedMetric.usesTimelineBand {
                    ForEach(Array(timelineLabels.enumerated()), id: \.offset) { offset, label in
                        Text(label)
                        if offset != timelineLabels.count - 1 { Spacer() }
                    }
                } else {
                    Text("current value scale")
                    Spacer()
                    if hasComparison {
                        Text("reference shown in detail")
                    } else {
                        Text("not a timeline")
                    }
                }
            }
            Text(selectedMetric.valueHeader)
                .frame(width: 82, alignment: .trailing)
            Text(hasComparison ? "change" : "read")
                .frame(width: 92, alignment: .trailing)
        }
        .font(CTTFont.mono(10, weight: .bold))
        .tracking(1.0)
        .textCase(.uppercase)
        .foregroundStyle(CTTColor.fg3(scheme))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(CTTColor.panel(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
        }
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Text("median current")
                .font(CTTFont.label(10))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.fg3(scheme))
            Text(cohortMedian)
                .font(CTTFont.mono(13, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))

            Text("current range")
                .font(CTTFont.label(10))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.fg3(scheme))
            Text(cohortSpread)
                .font(CTTFont.mono(13, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))

            Spacer()

            Text(cohortRead)
                .font(CTTFont.ui(12, weight: .semibold))
                .foregroundStyle(CTTColor.fg2(scheme))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)

            Button {
                openSelected()
            } label: {
                Label("Open transmitter", systemImage: "sidebar.right")
                    .font(CTTFont.ui(12, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(CTTColor.accent(scheme))
            .disabled(selectedIMEI == nil)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(CTTColor.paper(scheme))
        .overlay(alignment: .top) {
            Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
        }
    }

    private var timelineLabels: [String] {
        devices.first(where: { !$0.timelineLabels.isEmpty })?.timelineLabels ?? []
    }

    private var hasComparison: Bool {
        devices.contains { $0.hasComparison }
    }

    private var metricValues: [Double] {
        devices.compactMap { $0.rawMetricValue(for: selectedMetric) }.sorted()
    }

    private var cohortMedian: String {
        guard !metricValues.isEmpty else { return "not exposed" }
        let middle = metricValues.count / 2
        let value = metricValues.count.isMultiple(of: 2)
            ? (metricValues[middle - 1] + metricValues[middle]) / 2
            : metricValues[middle]
        return selectedMetric.formatRawValue(value)
    }

    private var cohortSpread: String {
        guard let min = metricValues.first, let max = metricValues.last else { return "not exposed" }
        return "\(selectedMetric.formatRawValue(min))-\(selectedMetric.formatRawValue(max))"
    }

    private var cohortRead: String {
        let outliers = rankedDevices.filter { $0.cohortStatus(for: selectedMetric).isProblem }.prefix(2)
        guard !outliers.isEmpty else {
            return hasComparison
                ? "No obvious \(selectedMetric.title.lowercased()) outliers against the reference window."
                : "No obvious \(selectedMetric.title.lowercased()) health flags in this period."
        }
        let suffix = hasComparison ? " against reference." : " in this period."
        return "Watch " + outliers.map(\.shortIMEI).joined(separator: " and ") + suffix
    }
}

private struct CohortTimelineRow: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic
    let metric: DetailMetric
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(device.identityTitle)
                    .font(CTTFont.ui(13, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(device.cohortIdentitySubtitle)
                    .font(CTTFont.mono(11))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(device.cohortStatus(for: metric).text)
                    .font(CTTFont.ui(11, weight: .semibold))
                    .foregroundStyle(device.cohortStatus(for: metric).color(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 230, alignment: .leading)

            CohortMetricBand(device: device, metric: metric)
                .frame(maxWidth: .infinity)

            Text(device.metricDisplay(for: metric))
                .font(CTTFont.mono(14, weight: .bold))
                .foregroundStyle(device.cohortStatus(for: metric).color(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 82, alignment: .trailing)

            Text(device.metricDeltaDisplay(for: metric))
                .font(CTTFont.mono(12, weight: .bold))
                .foregroundStyle(device.cohortStatus(for: metric).color(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .frame(width: 92, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? CTTColor.rowSelected(scheme) : CTTColor.paper(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct CohortMetricBand: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic
    let metric: DetailMetric

    var body: some View {
        if metric.usesTimelineBand, device.hasUsefulTimeline {
            BucketEventBand(
                buckets: device.connectionBuckets,
                style: metric == .connections ? .connections : .gpsFixes,
                height: 26
            )
        } else {
            MetricComparisonBand(device: device, metric: metric, height: 31)
        }
    }
}

private struct MetricComparisonBand: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic
    let metric: DetailMetric
    var height: CGFloat

    var body: some View {
        VStack(spacing: max(3, height * 0.12)) {
            Bar(value: device.normalizedMetricValue(for: metric), color: device.cohortStatus(for: metric).color(scheme))
                .frame(height: max(5, height * 0.48))
            if device.hasComparison {
                Bar(value: device.normalizedPriorMetricValue(for: metric), color: CTTColor.ghost(scheme))
                    .frame(height: max(4, height * 0.34))
            }
        }
        .frame(height: height)
    }
}

private struct DeviceLifelineList: View {
    @Environment(\.colorScheme) private var scheme
    let devices: [DeviceDiagnostic]
    let totalDeviceCount: Int
    @Binding var searchText: String
    let sortMode: LifelineSortMode
    @Binding var selectedIMEI: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(devices.count) of \(totalDeviceCount) devices · \(sortMode.caption)")
                        .font(CTTFont.label(10))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .lineLimit(1)
                    Spacer()
                    Text("▮ now · ▮ prior")
                        .font(CTTFont.mono(10))
                        .foregroundStyle(CTTColor.fg3(scheme))
                }

                LifelineSearchField(text: $searchText)
            }
            .padding(12)
            .background(CTTColor.panel(scheme))
            .overlay(alignment: .bottom) {
                Rectangle().fill(CTTColor.line(scheme)).frame(height: 1)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(devices) { device in
                        DeviceLifelineRow(device: device, isSelected: selectedIMEI == device.id)
                            .onTapGesture {
                                selectedIMEI = device.id
                            }
                    }
                }
            }
        }
        .background(CTTColor.panel(scheme))
    }
}

private struct LifelineSearchField: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CTTColor.fg3(scheme))
                .frame(width: 14)
            TextField("Search devices", text: $text)
                .textFieldStyle(.plain)
                .font(CTTFont.ui(13, weight: .medium))
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CTTColor.fg3(scheme))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct DeviceLifelineRow: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(device.verdictColor(scheme))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.identityTitle)
                            .font(device.hasAlias ? CTTFont.ui(12, weight: .bold) : CTTFont.mono(11, weight: .bold))
                            .foregroundStyle(isSelected ? CTTColor.ink(scheme) : CTTColor.fg2(scheme))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if device.hasAlias {
                            Text("IMEI \(device.shortIMEI)")
                                .font(CTTFont.mono(9))
                                .foregroundStyle(CTTColor.fg3(scheme))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Text(device.basisLabel)
                        .font(CTTFont.mono(9, weight: .bold))
                        .foregroundStyle(device.basisColor(scheme))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(device.basisColor(scheme).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(device.verdict)
                        .font(CTTFont.mono(11, weight: .bold))
                        .foregroundStyle(device.verdictColor(scheme))
                        .lineLimit(1)
                }

                LifelineRibbon(segments: device.segments, height: 24)

                Text(device.summary)
                    .font(CTTFont.ui(11, weight: .medium))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(isSelected ? CTTColor.rowSelected(scheme) : CTTColor.panel(scheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CTTColor.line2(scheme))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct LifelineDetail: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic
    @Binding var selectedMetric: DetailMetric

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.detailTitle)
                        .font(device.hasAlias ? CTTFont.ui(18, weight: .bold) : CTTFont.mono(15, weight: .bold))
                        .foregroundStyle(CTTColor.ink(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(device.detailSubtitle)
                        .font(CTTFont.ui(12, weight: .medium))
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(device.deviceFlagPill)
                    .font(CTTFont.ui(13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(device.verdictColor(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(CTTColor.canvas(scheme))
            .overlay(alignment: .bottom) {
                Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 13) {
                    HeroLifelineCard(device: device)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 180), spacing: 11), count: 3), spacing: 11) {
                        MetricVerdictCard(metric: .gpsSuccess, value: device.gpsMetric, delta: device.gpsDelta, color: device.gpsColor(scheme), selectedMetric: $selectedMetric)
                        MetricVerdictCard(metric: .fixTime, value: device.fixTimeMetric, delta: device.fixDelta, color: device.fixColor(scheme), selectedMetric: $selectedMetric)
                        MetricVerdictCard(metric: .connections, value: device.connectionMetric, delta: device.connectionDelta, color: device.connectionColor(scheme), selectedMetric: $selectedMetric)
                        MetricVerdictCard(metric: .solar, value: device.solarMetric, delta: device.solarDelta, color: device.solarColor(scheme), selectedMetric: $selectedMetric)
                        MetricVerdictCard(metric: .battery, value: device.batteryMetric, delta: device.batteryDelta, color: device.batteryColor(scheme), selectedMetric: $selectedMetric)
                        MetricVerdictCard(metric: .activity, value: device.activityMetric, delta: device.activityDelta, color: device.activityColor(scheme), selectedMetric: $selectedMetric)
                    }

                    MetricDetailPanel(metric: selectedMetric, device: device)

                    if selectedMetric.usesFixMap {
                        HStack(alignment: .top, spacing: 12) {
                            FixMapCard(device: device)
                            ReadCard(device: device)
                                .frame(width: 320)
                        }
                    } else {
                        ReadCard(device: device)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PairedLedgerPreview(device: device)
                }
                .padding(16)
            }
            .background(CTTColor.canvas(scheme))
        }
    }
}

private struct HeroLifelineCard: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(device.current == nil ? "GPS fix timeline — no analysis run" : "GPS fix timeline — pulled data window")
                    .font(CTTFont.label(10))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.fg2(scheme))
                Spacer()
                Text(device.current == nil ? "current window · not analyzed" : "current window · \(device.windowCount)")
                    .font(CTTFont.mono(10))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
            }

            ZStack(alignment: .topLeading) {
                LifelineRibbon(segments: device.segments, height: 92, isHero: true)
                if device.hasGap {
                    Text(device.gapLabel)
                        .font(CTTFont.ui(10, weight: .semibold))
                        .foregroundStyle(CTTColor.vermilion(scheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .offset(y: 66)
                }
                if device.hasFallback {
                    Text("cell-locate fixes · sparse")
                        .font(CTTFont.ui(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(CTTColor.fallback(scheme))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .offset(y: -2)
                }
            }

            HStack {
                ForEach(Array(device.timelineLabels.enumerated()), id: \.offset) { offset, label in
                    Text(label)
                        .font(CTTFont.mono(10))
                        .foregroundStyle(CTTColor.fg3(scheme))
                    if offset != device.timelineLabels.count - 1 { Spacer() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Connection check-ins")
                    .font(CTTFont.label(10))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.fg3(scheme))
                BucketEventBand(buckets: device.connectionBuckets, style: .connections, height: 28)
            }
        }
        .padding(15)
        .cttCard(radius: 9)
    }
}

private struct MetricVerdictCard: View {
    @Environment(\.colorScheme) private var scheme
    let metric: DetailMetric
    let value: String
    let delta: String
    let color: Color
    @Binding var selectedMetric: DetailMetric

    var body: some View {
        Button {
            selectedMetric = metric
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: metric.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(metric.title)
                        .font(CTTFont.label(10))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: selectedMetric == metric ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedMetric == metric ? color : CTTColor.fg3(scheme))
                }
                Text(value)
                    .font(CTTFont.mono(28, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(delta)
                    .font(CTTFont.mono(12))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selectedMetric == metric ? color.opacity(0.10) : CTTColor.paper(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .top) {
                Rectangle().fill(color).frame(height: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedMetric == metric ? color : CTTColor.line2(scheme), lineWidth: selectedMetric == metric ? 1.7 : 1)
            }
            .shadow(color: selectedMetric == metric ? color.opacity(0.12) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(metric.title) details")
    }
}

private struct MetricDetailPanel: View {
    @Environment(\.colorScheme) private var scheme
    let metric: DetailMetric
    let device: DeviceDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(metric.title, systemImage: metric.systemImage)
                    .font(CTTFont.label(11))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(color)
                InfoPopoverButton(
                    title: "\(metric.title) evidence",
                    message: explanation,
                    bullets: [
                        device.hasComparison
                            ? "Columns compare the current window against the reference window. Missing values mean the API did not expose enough records for that metric in this run."
                            : "This run has one current window. Rows show absolute values for the selected data period; missing values mean the API did not expose that metric."
                    ],
                    width: 390
                )
                Spacer()
                Text(device.metricWindowLabel)
                    .font(CTTFont.mono(10))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 520, alignment: .trailing)
            }

            if metric == .gpsSuccess {
                GPSOutcomeMixPanel(
                    current: GPSOutcomeBreakdown(window: device.current, title: device.hasComparison ? "Current" : "Observed period"),
                    prior: device.hasComparison ? GPSOutcomeBreakdown(window: device.prior, title: "Reference") : nil
                )
            }

            if metric == .battery {
                BatteryRechargePanel(
                    points: device.currentBatteryPoints,
                    summary: device.batteryRechargeSummary,
                    hasRetainedTrace: device.hasBatteryTrace
                )
            }

            MetricEvidenceLedger(rows: rows, color: color, showsComparison: device.hasComparison)
        }
        .padding(13)
        .cttCard(radius: 8)
    }

    private var color: Color {
        switch metric {
        case .gpsSuccess: return device.gpsColor(scheme)
        case .fixTime: return device.fixColor(scheme)
        case .connections: return device.connectionColor(scheme)
        case .solar: return device.solarColor(scheme)
        case .battery: return device.batteryColor(scheme)
        case .activity: return device.activityColor(scheme)
        }
    }

    private var explanation: String {
        switch metric {
        case .gpsSuccess:
            return "GPS outcome summarizes observed GPS fixes, observed non-GPS location fixes, and unresolved no-location attempts only when the stored denominator implies attempts beyond known fixes."
        case .fixTime:
            return "Fix time is the median time-to-fix for GPS fixes. The cadence row shows median time between GPS fixes."
        case .connections:
            return "Connections count check-ins in the window. Failure rate is only shown when the API provides success/failure fields on connection records."
        case .solar:
            return "Solar summarizes exposed solar samples: percent of solar samples with current or voltage, average millivolts, and average milliamps."
        case .battery:
            return "Battery uses median voltage, first-to-last voltage trend, and a retained voltage trace for recharge recovery when timestamped battery samples are available."
        case .activity:
            return "Activity uses accelerometer/activity samples exposed by the API. Mean activity is the average sample value; activity load is the cumulative counter delta when exposed, otherwise the sum of observed activity samples."
        }
    }

    private var rows: [MetricDetailRow] {
        switch metric {
        case .gpsSuccess:
            return [
                device.detailRow("GPS fix yield", current: device.current?.gpsSuccessRate, prior: device.prior?.gpsSuccessRate, format: .percentPoints),
                device.detailRow("GPS fixes", current: device.current?.gpsFixCount, prior: device.prior?.gpsFixCount, format: .count),
                device.detailRow("Non-GPS location fixes", current: device.current?.fallbackFixCount, prior: device.prior?.fallbackFixCount, format: .count)
            ]
        case .fixTime:
            return [
                device.detailRow("Median TTF", current: device.current?.medianTimeToFixSeconds, prior: device.prior?.medianTimeToFixSeconds, format: .seconds),
                device.detailRow("Fix cadence", current: device.current?.gpsFixCadenceHours, prior: device.prior?.gpsFixCadenceHours, format: .hours),
                device.detailRow("GPS fixes", current: device.current?.gpsFixCount, prior: device.prior?.gpsFixCount, format: .count)
            ]
        case .connections:
            return [
                device.detailRow("Check-ins", current: device.current?.connectionCount, prior: device.prior?.connectionCount, format: .count),
                device.detailRow("Failure rate", current: device.current?.connectionFailureRate, prior: device.prior?.connectionFailureRate, format: .percentPoints),
                device.detailRow("Check-in cadence", current: device.current?.checkInCadenceHours, prior: device.prior?.checkInCadenceHours, format: .hours)
            ]
        case .solar:
            return [
                device.detailRow("Solar exposure", current: device.current?.solarExposureRate, prior: device.prior?.solarExposureRate, format: .percentPoints),
                device.detailRow("Average voltage", current: device.current?.solarMillivolts, prior: device.prior?.solarMillivolts, format: .millivolts),
                device.detailRow("Average current", current: device.current?.solarMilliamps, prior: device.prior?.solarMilliamps, format: .milliamps)
            ]
        case .battery:
            return [
                device.detailRow("Median voltage", current: device.current?.medianBatteryVoltage, prior: device.prior?.medianBatteryVoltage, format: .volts),
                device.detailRow("Voltage trend", current: device.current?.batteryTrendVoltsPerDay, prior: device.prior?.batteryTrendVoltsPerDay, format: .voltsPerDay),
                device.detailRow("Resets", current: device.current?.resetCount, prior: device.prior?.resetCount, format: .count)
            ]
        case .activity:
            return [
                device.detailRow("Mean activity", current: device.current?.activityMean, prior: device.prior?.activityMean, format: .decimal),
                device.detailRow("Activity load", current: device.current?.activityCumulative, prior: device.prior?.activityCumulative, format: .decimal),
                device.detailRow("Temperature", current: device.current?.temperatureCelsius, prior: device.prior?.temperatureCelsius, format: .celsius)
            ]
        }
    }
}

private struct GPSOutcomeMixPanel: View {
    @Environment(\.colorScheme) private var scheme
    let current: GPSOutcomeBreakdown
    let prior: GPSOutcomeBreakdown?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("GPS Outcome Mix")
                    .font(CTTFont.label(11))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.fg3(scheme))
                InfoPopoverButton(
                    title: "GPS outcome mix",
                    message: "This graph combines observed GPS fixes and observed non-GPS location fixes in the same denominator. Red appears only when the stored GPS denominator implies attempts with no location record.",
                    bullets: [
                        "Green: GPS position records.",
                        "Blue: non-GPS location records such as cell-locate, Argos, Iridium, or unknown positioned fixes.",
                        "Red: unresolved no-location attempts inferred from the stored denominator; if the API does not expose that denominator, red is not shown."
                    ],
                    width: 430
                )
                Spacer()
                Text(prior == nil ? "current-period outcomes" : "current vs reference outcomes")
                    .font(CTTFont.mono(10))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
            }

            GPSOutcomeMixRow(breakdown: current)

            if let prior {
                GPSOutcomeMixRow(breakdown: prior)
            }

            HStack(spacing: 10) {
                GPSOutcomeLegendChip(label: "GPS fix", color: CTTColor.green(scheme))
                GPSOutcomeLegendChip(label: "Non-GPS location", color: CTTColor.fallback(scheme))
                GPSOutcomeLegendChip(label: "Unresolved no-location", color: CTTColor.vermilion(scheme))
                Spacer(minLength: 0)
            }
        }
        .padding(11)
        .background(CTTColor.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct GPSOutcomeMixRow: View {
    @Environment(\.colorScheme) private var scheme
    let breakdown: GPSOutcomeBreakdown

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(breakdown.title)
                    .font(CTTFont.ui(12, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                if breakdown.totalOutcomes > 0 {
                    Text("\(breakdown.gpsFixes) GPS · \(breakdown.nonGPSLocationFixes) non-GPS · \(breakdown.unresolvedNoLocationAttempts) unresolved")
                        .font(CTTFont.mono(10))
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text("no exposed location outcomes")
                        .font(CTTFont.mono(10))
                        .foregroundStyle(CTTColor.fg3(scheme))
                }
                Spacer()
                Text(breakdown.gpsYieldText)
                    .font(CTTFont.mono(11, weight: .bold))
                    .foregroundStyle(breakdown.totalOutcomes > 0 ? CTTColor.green(scheme) : CTTColor.fg3(scheme))
            }

            GPSOutcomeStackedBar(breakdown: breakdown)
                .frame(height: 18)
                .help(breakdown.helpText)
        }
        .padding(10)
        .background(CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct GPSOutcomeStackedBar: View {
    @Environment(\.colorScheme) private var scheme
    let breakdown: GPSOutcomeBreakdown

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let gpsWidth = width * breakdown.gpsFraction
            let nonGPSWidth = width * breakdown.nonGPSFraction
            let unresolvedWidth = width * breakdown.unresolvedFraction

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(CTTColor.track(scheme))

                GPSOutcomeSegment(
                    width: gpsWidth,
                    offset: 0,
                    color: CTTColor.green(scheme),
                    cornerRadius: 5
                )

                GPSOutcomeSegment(
                    width: nonGPSWidth,
                    offset: gpsWidth,
                    color: CTTColor.fallback(scheme),
                    cornerRadius: 0
                )

                GPSOutcomeSegment(
                    width: unresolvedWidth,
                    offset: gpsWidth + nonGPSWidth,
                    color: CTTColor.vermilion(scheme),
                    cornerRadius: unresolvedWidth >= width - 1 ? 5 : 0
                )
            }
        }
    }
}

private struct GPSOutcomeSegment: View {
    let width: CGFloat
    let offset: CGFloat
    let color: Color
    let cornerRadius: CGFloat

    var body: some View {
        if width > 0 {
            Rectangle()
                .fill(color)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .frame(width: max(width, 3))
                .offset(x: offset)
        }
    }
}

private struct GPSOutcomeLegendChip: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(CTTFont.mono(9, weight: .bold))
                .foregroundStyle(CTTColor.fg3(scheme))
                .lineLimit(1)
        }
    }
}

private struct GPSOutcomeBreakdown {
    let title: String
    let gpsFixes: Int
    let nonGPSLocationFixes: Int
    let unresolvedNoLocationAttempts: Int
    let totalOutcomes: Int

    init(window: DeviceWindowMetrics?, title: String) {
        self.title = title

        let gpsFixes = max(0, window?.gpsFixCount ?? 0)
        let nonGPSLocationFixes = max(0, window?.fallbackFixCount ?? 0)
        let knownLocationOutcomes = gpsFixes + nonGPSLocationFixes
        let inferredDenominator: Int

        if let rate = window?.gpsSuccessRate, rate > 0 {
            inferredDenominator = Int((Double(gpsFixes) / rate).rounded())
        } else {
            inferredDenominator = knownLocationOutcomes
        }

        let totalOutcomes = max(knownLocationOutcomes, inferredDenominator)

        self.gpsFixes = gpsFixes
        self.nonGPSLocationFixes = nonGPSLocationFixes
        self.unresolvedNoLocationAttempts = max(0, totalOutcomes - knownLocationOutcomes)
        self.totalOutcomes = totalOutcomes
    }

    var gpsFraction: Double {
        fraction(Double(gpsFixes))
    }

    var nonGPSFraction: Double {
        fraction(Double(nonGPSLocationFixes))
    }

    var unresolvedFraction: Double {
        fraction(Double(unresolvedNoLocationAttempts))
    }

    var gpsYieldText: String {
        guard totalOutcomes > 0 else { return "not exposed" }
        return "\(Int((Double(gpsFixes) / Double(totalOutcomes) * 100).rounded()))% GPS"
    }

    var helpText: String {
        guard totalOutcomes > 0 else {
            return "\(title): no GPS or non-GPS location records were exposed for this window."
        }
        return "\(title): \(gpsFixes) GPS fixes, \(nonGPSLocationFixes) non-GPS location fixes, \(unresolvedNoLocationAttempts) unresolved no-location attempts, \(totalOutcomes) total classified outcomes."
    }

    private func fraction(_ value: Double) -> Double {
        guard totalOutcomes > 0 else { return 0 }
        return max(0, min(1, value / Double(totalOutcomes)))
    }
}

private struct BatteryRechargePanel: View {
    @Environment(\.colorScheme) private var scheme
    let points: [DeviceBatteryPoint]
    let summary: BatteryRechargeSummary
    let hasRetainedTrace: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recharge recovery")
                    .font(CTTFont.label(11))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(recoveryColor)
                InfoPopoverButton(
                    title: "Recharge recovery",
                    message: "This is a voltage-cycle screen. It looks for observed battery drops and later voltage rebounds in the selected data window.",
                    bullets: [
                        "Discharge event: battery falls by at least 0.03 V from a recent high.",
                        "Recovered event: after that drop, voltage rises by at least 0.02 V from the low point.",
                        "This does not prove solar causality by itself; use Solar details to inspect panel signal."
                    ],
                    width: 420
                )
                Spacer()
                Text(windowText)
                    .font(CTTFont.mono(10))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
            }

            if summary.sampleCount >= 3 {
                BatteryRechargeSparkline(points: points)
                    .frame(height: 86)

                HStack(spacing: 10) {
                    BatteryRechargeStat(
                        title: "Recovered drops",
                        value: "\(summary.recoveredEvents)/\(summary.dischargeEvents)",
                        color: recoveryColor
                    )
                    BatteryRechargeStat(
                        title: "Median recovery",
                        value: recoveryTimeText,
                        color: CTTColor.fg2(scheme)
                    )
                    BatteryRechargeStat(
                        title: "Largest drop",
                        value: largestDropText,
                        color: CTTColor.fg2(scheme)
                    )
                    BatteryRechargeStat(
                        title: "Net change",
                        value: netChangeText,
                        color: netChangeColor
                    )
                }

                Text(readText)
                    .font(CTTFont.ui(12, weight: .semibold))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(emptyText)
                    .font(CTTFont.ui(13, weight: .semibold))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CTTColor.paper(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(11)
        .background(CTTColor.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }

    private var recoveryColor: Color {
        guard summary.dischargeEvents > 0 else { return CTTColor.green(scheme) }
        if summary.unrecoveredEvents == 0 { return CTTColor.green(scheme) }
        if summary.recoveredEvents > 0 { return CTTColor.ochre(scheme) }
        return CTTColor.vermilion(scheme)
    }

    private var netChangeColor: Color {
        guard let start = summary.startVoltage, let end = summary.endVoltage else { return CTTColor.fg2(scheme) }
        if end < start - 0.05 { return CTTColor.ochre(scheme) }
        return CTTColor.green(scheme)
    }

    private var windowText: String {
        guard let start = summary.startDate, let end = summary.endDate else { return "no voltage trace" }
        return "\(summary.sampleCount) samples · \(Formatters.shortDateTime.string(from: start)) → \(Formatters.shortDateTime.string(from: end))"
    }

    private var recoveryTimeText: String {
        guard let hours = summary.medianRecoveryHours else { return "—" }
        return hours >= 24 ? String(format: "%.1fd", hours / 24) : String(format: "%.1fh", hours)
    }

    private var largestDropText: String {
        guard let volts = summary.largestDropVolts else { return "—" }
        return String(format: "%.2f V", volts)
    }

    private var netChangeText: String {
        guard let start = summary.startVoltage, let end = summary.endVoltage else { return "—" }
        return String(format: "%+.2f V", end - start)
    }

    private var readText: String {
        if summary.dischargeEvents == 0 {
            return "No battery drop of 0.03 V or more was detected in this window, so there was no recharge cycle to score."
        }
        if summary.unrecoveredEvents == 0 {
            return "Every observed discharge recovered by at least 0.02 V. That supports a normal recharge pattern in this window."
        }
        return "\(summary.recoveredEvents) of \(summary.dischargeEvents) observed discharges recovered by at least 0.02 V. Review the unrecovered drop before calling power stable."
    }

    private var emptyText: String {
        if !hasRetainedTrace {
            return "This run was created before battery voltage traces were retained. Re-run the analysis to evaluate recharge recovery."
        }
        return "Recharge recovery needs at least 3 timestamped battery voltage samples in the selected window."
    }
}

private struct BatteryRechargeSparkline: View {
    @Environment(\.colorScheme) private var scheme
    let points: [DeviceBatteryPoint]

    var body: some View {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let voltages = sorted.map(\.voltage)
        let minVoltage = voltages.min() ?? 0
        let maxVoltage = voltages.max() ?? 1

        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                guard sorted.count > 1 else { return }

                let range = max(0.08, maxVoltage - minVoltage)
                let topPadding: CGFloat = 8
                let bottomPadding: CGFloat = 8
                let usableHeight = max(1, size.height - topPadding - bottomPadding)

                func point(_ index: Int) -> CGPoint {
                    let fractionX = Double(index) / Double(max(1, sorted.count - 1))
                    let fractionY = (sorted[index].voltage - minVoltage) / range
                    return CGPoint(
                        x: size.width * fractionX,
                        y: topPadding + usableHeight * (1 - fractionY)
                    )
                }

                let baseline = Path(CGRect(x: 0, y: topPadding + usableHeight, width: size.width, height: 1))
                context.fill(baseline, with: .color(CTTColor.line2(scheme)))

                for index in 0..<(sorted.count - 1) {
                    var path = Path()
                    path.move(to: point(index))
                    path.addLine(to: point(index + 1))
                    let color = sorted[index + 1].voltage >= sorted[index].voltage
                        ? CTTColor.green(scheme)
                        : CTTColor.ochre(scheme)
                    context.stroke(path, with: .color(color), lineWidth: 2.5)
                }
            }
            .background(CTTColor.paper(scheme))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CTTColor.line2(scheme), lineWidth: 1)
            }

            HStack {
                Text(String(format: "low %.2fV", minVoltage))
                Spacer()
                HStack(spacing: 12) {
                    Label("charging", systemImage: "arrow.up.right")
                        .foregroundStyle(CTTColor.green(scheme))
                    Label("discharging", systemImage: "arrow.down.right")
                        .foregroundStyle(CTTColor.ochre(scheme))
                }
                Spacer()
                Text(String(format: "high %.2fV", maxVoltage))
            }
            .font(CTTFont.mono(9, weight: .bold))
            .foregroundStyle(CTTColor.fg3(scheme))
        }
    }
}

private struct BatteryRechargeStat: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(CTTFont.label(8))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.fg3(scheme))
            Text(value)
                .font(CTTFont.mono(12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 9)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .background(CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct MetricEvidenceLedger: View {
    @Environment(\.colorScheme) private var scheme
    let rows: [MetricDetailRow]
    let color: Color
    let showsComparison: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Evidence")
                Spacer()
                Text(showsComparison ? "current · prior · change" : "current-period values")
            }
            .font(CTTFont.label(11))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(CTTColor.fg3(scheme))

            ForEach(rows) { row in
                MetricEvidenceRow(row: row, color: color, showsComparison: showsComparison)
            }
        }
    }
}

private struct MetricEvidenceRow: View {
    @Environment(\.colorScheme) private var scheme
    let row: MetricDetailRow
    let color: Color
    let showsComparison: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(CTTFont.ui(13, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                if showsComparison {
                    Text(row.change)
                        .font(CTTFont.mono(12, weight: .bold))
                        .foregroundStyle(row.isImportant ? .white : color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(row.isImportant ? color : color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(spacing: 10) {
                MetricValueBlock(title: showsComparison ? "current" : "value", value: row.current, prominent: true, color: color)

                if showsComparison {
                    MetricValueBlock(title: "prior", value: row.prior, prominent: false, color: color)
                }

                MetricEvidenceBars(
                    current: row.currentBar,
                    prior: row.priorBar,
                    color: color,
                    showsComparison: showsComparison
                )
            }
        }
        .padding(11)
        .background(CTTColor.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct MetricEvidenceBars: View {
    @Environment(\.colorScheme) private var scheme
    let current: Double
    let prior: Double
    let color: Color
    let showsComparison: Bool

    var body: some View {
        VStack(spacing: 5) {
            Bar(value: current, color: color)
                .frame(height: 10)
            if showsComparison {
                Bar(value: prior, color: CTTColor.ghost(scheme))
                    .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MetricValueBlock: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let value: String
    let prominent: Bool
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(CTTFont.label(9))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.fg3(scheme))
            Text(value)
                .font(CTTFont.mono(13, weight: prominent ? .bold : .regular))
                .foregroundStyle(prominent ? color : CTTColor.fg2(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .frame(width: 134, height: 36, alignment: .leading)
        .background(prominent ? color.opacity(0.10) : CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct MetricDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let current: String
    let prior: String
    let change: String
    let isImportant: Bool
    let currentBar: Double
    let priorBar: Double
}

private enum MetricDetailFormat {
    case count
    case decimal
    case percentPoints
    case seconds
    case hours
    case volts
    case voltsPerDay
    case millivolts
    case milliamps
    case celsius
}

private struct FixMapCard: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic
    @State private var selectedPoint: MapPoint?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var showsGPSFixes = true
    @State private var showsCellLocateFixes = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            if device.mapPoints.isEmpty {
                EmptyFixMap(message: "No mapped fixes in this run")
            } else if visiblePoints.isEmpty {
                EmptyFixMap(message: "No visible fixes for this map filter")
            } else {
                Map(position: $mapPosition) {
                    ForEach(visiblePoints) { point in
                        Annotation(point.annotationTitle, coordinate: point.coordinate) {
                            Button {
                                selectedPoint = point
                            } label: {
                                FixMapMarker(point: point)
                                    .padding(8)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(point.annotationTitle)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .popover(item: $selectedPoint) { point in
                    FixPointPopover(point: point)
                }
            }

            HStack(spacing: 8) {
                Text("Fix map · GPS vs cell-locate markers")
                    .font(CTTFont.label(11))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    FixMapFilterButton(
                        label: "GPS",
                        color: CTTColor.green(scheme),
                        isOn: showsGPSFixes,
                        action: toggleGPSFixes
                    )
                    .help("Show GPS fixes on the map.")

                    FixMapFilterButton(
                        label: "Cell-locate",
                        color: CTTColor.fallback(scheme),
                        isOn: showsCellLocateFixes,
                        action: toggleCellLocateFixes
                    )
                    .help("Show cell-locate fixes on the map.")

                    Button {
                        zoomToLatestVisibleFix()
                    } label: {
                        Label("Latest", systemImage: "scope")
                            .font(CTTFont.ui(10, weight: .bold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(latestVisiblePoint == nil ? CTTColor.fg3(scheme) : CTTColor.ink(scheme))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(latestVisiblePoint == nil ? CTTColor.track(scheme).opacity(0.55) : CTTColor.paper(scheme).opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(latestVisiblePoint == nil)
                    .help("Zoom to the latest visible fix. If only GPS is visible, this zooms to the latest GPS fix; if only cell-locate is visible, it zooms to the latest cell-locate fix.")
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(10)

            if let selectedPoint {
                FixPointCallout(point: selectedPoint) {
                    self.selectedPoint = nil
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(.opacity)
            }
        }
        .frame(minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
        .onAppear(perform: fitVisiblePoints)
        .onChange(of: device.id) { _, _ in
            selectedPoint = nil
            showsGPSFixes = true
            showsCellLocateFixes = true
            fitVisiblePoints()
        }
        .onChange(of: visiblePointIDs) { _, _ in
            if let selectedPoint, !visiblePointIDs.contains(selectedPoint.id) {
                self.selectedPoint = nil
            }
            fitVisiblePoints()
        }
    }

    private var visiblePoints: [MapPoint] {
        device.mapPoints.filter { point in
            if point.isFallback {
                return showsCellLocateFixes
            }
            return showsGPSFixes
        }
    }

    private var visiblePointIDs: [Int] {
        visiblePoints.map(\.id)
    }

    private var latestVisiblePoint: MapPoint? {
        visiblePoints.max { lhs, rhs in
            lhs.timestamp < rhs.timestamp
        }
    }

    private var visibleMapRegion: MKCoordinateRegion {
        Self.region(for: visiblePoints) ?? Self.region(for: device.mapPoints) ?? Self.defaultMapRegion
    }

    private static var defaultMapRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 35, longitudeDelta: 55)
        )
    }

    private static func region(for points: [MapPoint]) -> MKCoordinateRegion? {
        guard !points.isEmpty else {
            return nil
        }
        let lats = points.map(\.lat)
        let lons = points.map(\.lon)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.45, 0.01),
                longitudeDelta: max((maxLon - minLon) * 1.45, 0.01)
            )
        )
    }

    private func toggleGPSFixes() {
        if showsGPSFixes && !showsCellLocateFixes {
            showsCellLocateFixes = true
        }
        showsGPSFixes.toggle()
    }

    private func toggleCellLocateFixes() {
        if showsCellLocateFixes && !showsGPSFixes {
            showsGPSFixes = true
        }
        showsCellLocateFixes.toggle()
    }

    private func fitVisiblePoints() {
        guard !visiblePoints.isEmpty else {
            return
        }
        mapPosition = .region(visibleMapRegion)
    }

    private func zoomToLatestVisibleFix() {
        guard let point = latestVisiblePoint else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: point.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
        }
        selectedPoint = point
    }
}

private struct FixMapFilterButton: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let color: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isOn ? color : CTTColor.ghost(scheme))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(CTTFont.ui(10, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? CTTColor.ink(scheme) : CTTColor.fg3(scheme))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(isOn ? color.opacity(0.13) : CTTColor.track(scheme).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isOn ? color.opacity(0.35) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct FixPointCallout: View {
    @Environment(\.colorScheme) private var scheme
    let point: MapPoint
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(point.isFallback ? "Cell-locate fix" : "GPS fix")
                    .font(CTTFont.ui(12, weight: .bold))
                    .foregroundStyle(point.isFallback ? CTTColor.fallback(scheme) : CTTColor.green(scheme))
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CTTColor.fg3(scheme))
                }
                .buttonStyle(.plain)
            }

            Text(Formatters.shortDateTime.string(from: point.timestamp))
                .font(CTTFont.mono(11, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))

            Text("lat \(String(format: "%.5f", point.lat)) · lon \(String(format: "%.5f", point.lon))")
                .font(CTTFont.mono(10))
                .foregroundStyle(CTTColor.fg2(scheme))
                .lineLimit(1)

            HStack(spacing: 7) {
                metadataChip(point.typeLabel)
                if let timeToFix = point.timeToFix {
                    metadataChip("\(timeToFix)s TTF")
                }
                if let hdop = point.hdop {
                    metadataChip("HDOP \(String(format: "%.1f", hdop))")
                }
                if let satCount = point.satCount {
                    metadataChip("\(satCount) sats")
                }
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    private func metadataChip(_ text: String) -> some View {
        Text(text)
            .font(CTTFont.mono(9, weight: .bold))
            .foregroundStyle(CTTColor.fg2(scheme))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(CTTColor.paper(scheme).opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private struct EmptyFixMap: View {
    @Environment(\.colorScheme) private var scheme
    let message: String

    var body: some View {
        ZStack {
            DiagonalStripeBackground()
            Text(message)
                .font(CTTFont.ui(12, weight: .semibold))
                .foregroundStyle(CTTColor.fg3(scheme))
                .padding(.top, 34)
        }
    }
}

private struct FixMapMarker: View {
    @Environment(\.colorScheme) private var scheme
    let point: MapPoint

    var body: some View {
        Circle()
            .fill(point.isFallback ? CTTColor.fallback(scheme) : CTTColor.green(scheme))
            .frame(width: point.isFallback ? 11 : 10, height: point.isFallback ? 11 : 10)
            .overlay {
                Circle()
                    .stroke(.white, style: StrokeStyle(lineWidth: point.isFallback ? 2 : 1.5, dash: point.isFallback ? [2, 2] : []))
            }
            .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
            .help(point.annotationTitle)
    }
}

private struct FixPointPopover: View {
    @Environment(\.colorScheme) private var scheme
    let point: MapPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(point.isFallback ? "Cell-locate fix" : "GPS fix")
                    .font(CTTFont.ui(13, weight: .bold))
                    .foregroundStyle(point.isFallback ? CTTColor.fallback(scheme) : CTTColor.green(scheme))
                Spacer()
                Text(point.typeLabel)
                    .font(CTTFont.mono(11, weight: .bold))
                    .foregroundStyle(CTTColor.fg3(scheme))
            }

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                FixPointMetadataRow(label: "Fix", value: Formatters.shortDateTime.string(from: point.timestamp))
                FixPointMetadataRow(label: "Lat", value: String(format: "%.5f", point.lat))
                FixPointMetadataRow(label: "Lon", value: String(format: "%.5f", point.lon))
                if let timeToFix = point.timeToFix {
                    FixPointMetadataRow(label: "TTF", value: "\(timeToFix)s")
                }
                if let hdop = point.hdop {
                    FixPointMetadataRow(label: "HDOP", value: String(format: "%.1f", hdop))
                }
                if let satCount = point.satCount {
                    FixPointMetadataRow(label: "Sats", value: "\(satCount)")
                }
                if let uncertaintyM = point.uncertaintyM {
                    FixPointMetadataRow(label: "Uncertainty", value: "\(Int(uncertaintyM.rounded()))m")
                }
            }
        }
        .padding(12)
        .frame(width: 250)
    }
}

private struct FixPointMetadataRow: View {
    @Environment(\.colorScheme) private var scheme
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(CTTFont.label(10))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.fg3(scheme))
            Text(value)
                .font(CTTFont.mono(12))
                .foregroundStyle(CTTColor.ink(scheme))
                .textSelection(.enabled)
        }
    }
}

private struct ReadCard: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Read")
                .font(CTTFont.label(11))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(CTTColor.accent(scheme))
            Text(device.readText)
                .font(CTTFont.ui(13, weight: .medium))
                .lineSpacing(3)
                .foregroundStyle(CTTColor.ink(scheme))
        }
        .padding(13)
        .background(CTTColor.accentSoft(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct PairedLedgerPreview: View {
    @Environment(\.colorScheme) private var scheme
    let device: DeviceDiagnostic

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(device.hasComparison ? "Paired ledger" : "Current health ledger")
                    .font(CTTFont.label(12))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.fg3(scheme))
                InfoPopoverButton(
                    title: device.hasComparison ? "Paired ledger" : "Current health ledger",
                    message: device.hasComparison
                        ? "Rows compare the same pulled current and reference windows. Diverging rows are the audit trail behind the device flag."
                        : "Single-period health view: rows show pulled values for this window. Run a comparison when you need reference-window evidence.",
                    width: 370
                )
                Spacer()
                Text(device.hasComparison ? "A · current     B · reference (ghost)     change" : "current-period values")
                    .font(CTTFont.mono(11))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(CTTColor.titlebar(scheme))

            VStack(spacing: 0) {
                LedgerRow(metric: "GPS fix yield", current: device.gpsBar, prior: device.gpsPriorBar, verdict: device.hasComparison ? device.gpsDelta : device.gpsMetric, color: device.gpsColor(scheme), showsComparison: device.hasComparison)
                LedgerRow(metric: "Fix time", current: device.fixBar, prior: device.fixPriorBar, verdict: device.hasComparison ? device.fixDelta : device.fixTimeMetric, color: device.fixColor(scheme), showsComparison: device.hasComparison)
                LedgerRow(metric: "Connections", current: device.connectionBar, prior: device.connectionPriorBar, verdict: device.hasComparison ? device.connectionDelta : device.connectionMetric, color: device.connectionColor(scheme), showsComparison: device.hasComparison)
                LedgerRow(metric: "Solar", current: device.solarBar, prior: device.solarPriorBar, verdict: device.hasComparison ? device.solarDelta : device.solarMetric, color: device.solarColor(scheme), showsComparison: device.hasComparison)
                LedgerRow(metric: "Battery", current: device.batteryBar, prior: device.batteryPriorBar, verdict: device.hasComparison ? device.batteryDelta : device.batteryMetric, color: device.batteryColor(scheme), showsComparison: device.hasComparison)
                LedgerRow(metric: "ACC / activity", current: device.activityBar, prior: device.activityPriorBar, verdict: device.hasComparison ? device.activityDelta : device.activityMetric, color: device.activityColor(scheme), showsComparison: device.hasComparison, showsDivider: false)
            }

        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct LedgerRow: View {
    @Environment(\.colorScheme) private var scheme
    let metric: String
    let current: Double
    let prior: Double
    let verdict: String
    let color: Color
    let showsComparison: Bool
    var showsDivider = true

    var body: some View {
        HStack(spacing: 14) {
            Text(metric)
                .font(CTTFont.mono(13, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 132, alignment: .leading)

            Bar(value: current, color: color)
                .frame(height: 16)

            if showsComparison {
                Bar(value: prior, color: CTTColor.ghost(scheme))
                    .frame(height: 16)
            } else {
                Text("no prior")
                    .font(CTTFont.mono(11, weight: .bold))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .center)
                    .background(CTTColor.track(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            }

            Text(verdict)
                .font(CTTFont.mono(12, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8)
                .frame(width: 116, height: 30)
                .background(color.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CTTColor.paper(scheme))
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(CTTColor.line2(scheme))
                    .frame(height: 1)
            }
        }
    }
}

private struct Bar: View {
    @Environment(\.colorScheme) private var scheme
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(CTTColor.track(scheme))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: proxy.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 15)
    }
}

private struct LifelineRibbon: View {
    @Environment(\.colorScheme) private var scheme
    let segments: [LifelineSegment]
    var height: CGFloat
    var isHero = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(CTTColor.track(scheme))

                TickBand(color: CTTColor.ghost(scheme), tickWidth: isHero ? 2.5 : 1.5, gap: isHero ? 8 : 5)
                    .opacity(0.55)
                    .frame(height: isHero ? height * 0.62 : 8)
                    .offset(y: isHero ? 6 : 2)

                ForEach(segments) { segment in
                    segmentView(segment)
                        .frame(width: width * segment.width, height: segment.kind == .fallback && isHero ? height * 0.43 : currentHeight)
                        .offset(x: width * segment.start, y: currentOffset(for: segment.kind))
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var currentHeight: CGFloat {
        isHero ? height * 0.54 : 9
    }

    private func currentOffset(for kind: LifelineSegment.Kind) -> CGFloat {
        if isHero {
            return kind == .fallback ? 24 : 14
        }
        return height - 11
    }

    @ViewBuilder
    private func segmentView(_ segment: LifelineSegment) -> some View {
        switch segment.kind {
        case .gps:
            TickBand(color: CTTColor.green(scheme), tickWidth: isHero ? 2.5 : 1.5, gap: isHero ? 7 : 4)
        case .fallback:
            TickBand(color: CTTColor.fallback(scheme), tickWidth: isHero ? 2.5 : 1.5, gap: isHero ? 7 : 4)
        case .gap:
            Rectangle().fill(CTTColor.canvas(scheme))
        }
    }
}

private struct TickBand: View {
    let color: Color
    let tickWidth: CGFloat
    let gap: CGFloat

    var body: some View {
        Canvas { context, size in
            var x: CGFloat = 0
            while x < size.width {
                context.fill(
                    Path(CGRect(x: x, y: 0, width: tickWidth, height: size.height)),
                    with: .color(color)
                )
                x += gap
            }
        }
    }
}

private enum BucketEventBandStyle {
    case gpsFixes
    case connections
}

private struct BucketEventBand: View {
    @Environment(\.colorScheme) private var scheme
    @State private var selectedBucket: DeviceLifelineBucket?
    let buckets: [DeviceLifelineBucket]
    let style: BucketEventBandStyle
    var height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let bucketWidth = proxy.size.width / CGFloat(max(1, buckets.count))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(CTTColor.track(scheme))

                TickBand(color: CTTColor.ghost(scheme), tickWidth: 1.4, gap: 7)
                    .opacity(0.42)
                    .padding(.vertical, 4)

                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    BucketEventMark(
                        bucket: bucket,
                        style: style,
                        height: height,
                        width: bucketWidth,
                        selectedBucket: $selectedBucket
                    )
                    .offset(x: CGFloat(index) * bucketWidth)
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .popover(item: $selectedBucket) { bucket in
            BucketEventPopover(bucket: bucket, style: style)
        }
    }
}

private struct BucketEventMark: View {
    @Environment(\.colorScheme) private var scheme
    let bucket: DeviceLifelineBucket
    let style: BucketEventBandStyle
    let height: CGFloat
    let width: CGFloat
    @Binding var selectedBucket: DeviceLifelineBucket?

    var body: some View {
        Button {
            selectedBucket = bucket
        } label: {
            ZStack {
                Rectangle()
                    .fill(.clear)
                if let color = eventColor {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: markWidth, height: markHeight)
                }
            }
            .frame(width: max(4, width), height: height)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .disabled(eventColor == nil)
    }

    private var eventColor: Color? {
        switch style {
        case .gpsFixes:
            if bucket.gpsFixCount > 0 { return CTTColor.green(scheme) }
            if bucket.fallbackFixCount > 0 { return CTTColor.fallback(scheme) }
            return nil
        case .connections:
            return bucket.connectionCount > 0 ? CTTColor.green(scheme) : nil
        }
    }

    private var markHeight: CGFloat {
        switch style {
        case .gpsFixes:
            return bucket.fallbackFixCount > 0 && bucket.gpsFixCount == 0 ? height * 0.48 : height * 0.72
        case .connections:
            return height * 0.68
        }
    }

    private var markWidth: CGFloat {
        min(max(2.5, width * 0.22), 5)
    }

    private var helpText: String {
        let range = "\(Formatters.shortDateTime.string(from: bucket.startDate)) - \(Formatters.shortDateTime.string(from: bucket.endDate))"
        switch style {
        case .gpsFixes:
            return "\(range): \(bucket.gpsFixCount) GPS, \(bucket.fallbackFixCount) cell-locate, \(bucket.connectionCount) check-ins in this bucket"
        case .connections:
            return "\(range): \(bucket.connectionCount) check-ins"
        }
    }
}

private struct BucketEventPopover: View {
    @Environment(\.colorScheme) private var scheme
    let bucket: DeviceLifelineBucket
    let style: BucketEventBandStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(style == .connections ? "Check-in bucket" : "Fix bucket")
                .font(CTTFont.ui(14, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))
            Text("\(Formatters.shortDateTime.string(from: bucket.startDate)) - \(Formatters.shortDateTime.string(from: bucket.endDate))")
                .font(CTTFont.mono(11))
                .foregroundStyle(CTTColor.fg2(scheme))

            Divider()

            if style == .gpsFixes {
                bucketMetric("GPS fixes", bucket.gpsFixCount, color: CTTColor.green(scheme))
                bucketMetric("Cell-locate fixes", bucket.fallbackFixCount, color: CTTColor.fallback(scheme))
                bucketMetric("Check-ins in same bucket", bucket.connectionCount, color: CTTColor.green(scheme))
            } else {
                bucketMetric("Check-ins", bucket.connectionCount, color: CTTColor.green(scheme))
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }

    private func bucketMetric(_ title: String, _ value: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(CTTFont.ui(12, weight: .semibold))
            Spacer()
            Text("\(value)")
                .font(CTTFont.mono(12, weight: .bold))
        }
        .foregroundStyle(CTTColor.fg2(scheme))
    }
}

private struct DiagonalStripeBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CTTColor.map1(scheme)))
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                path.addLine(to: CGPoint(x: x + size.height + 11, y: 0))
                path.addLine(to: CGPoint(x: x + 11, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .color(CTTColor.map2(scheme)))
                x += 22
            }
        }
    }
}

private struct DeviceDiagnostic: Identifiable, Comparable {
    let device: ProjectDeviceListItem
    let analysis: DeviceAnalysisSummary?
    let run: AnalysisRun?
    let current: DeviceWindowMetrics?
    let prior: DeviceWindowMetrics?
    let severity: Severity
    let summary: String
    let score: Int?
    let segments: [LifelineSegment]
    let sampledMapPoints: [MapPoint]

    var id: String { device.imei }
    var aliasLabel: String? {
        guard let alias = device.alias?.trimmingCharacters(in: .whitespacesAndNewlines),
              !alias.isEmpty,
              alias != device.imei
        else {
            return nil
        }
        return alias
    }

    var hasAlias: Bool {
        aliasLabel != nil
    }

    var imeiTail: String {
        String(device.imei.suffix(5))
    }

    var shortIMEI: String {
        imeiTail
    }

    var identityTitle: String {
        if let aliasLabel {
            return "\(aliasLabel) · \(imeiTail)"
        }
        return shortIMEI
    }

    var detailTitle: String {
        if let aliasLabel {
            return "\(aliasLabel) · \(imeiTail)"
        }
        return "IMEI \(shortIMEI)"
    }

    var cohortIdentitySubtitle: String {
        if hasAlias {
            return "IMEI \(shortIMEI)"
        }
        return device.deviceType
    }

    var detailSubtitle: String {
        if hasAlias {
            return "IMEI \(device.imei) · \(device.deviceType) · \(lastFixText)"
        }
        return "\(device.deviceType) · IMEI \(device.imei) · \(lastFixText)"
    }

    init(device: ProjectDeviceListItem, analysis: DeviceAnalysisSummary?, run: AnalysisRun?) {
        let resolvedCurrent = analysis.flatMap { Self.currentWindow(from: $0.windows) }
        let resolvedPrior = analysis.flatMap { Self.priorWindow(from: $0.windows) }

        self.device = device
        self.analysis = analysis
        self.run = run
        self.current = resolvedCurrent
        self.prior = resolvedPrior

        if let analysis, let current = resolvedCurrent {
            self.segments = Self.segments(from: analysis.lifelineBuckets)
            self.sampledMapPoints = Self.mapPoints(from: analysis.fixPoints)

            if current.connectionCount == 0 && current.gpsFixCount == 0 && current.fallbackFixCount == 0 {
                self.severity = .below
                self.score = 100
                self.summary = "no telemetry records in \(current.title.lowercased())"
            } else if let prior = resolvedPrior {
                let gpsDrop = Self.dropFraction(current: current.gpsSuccessRate, prior: prior.gpsSuccessRate)
                let fixSlowdown = Self.increaseFraction(current: current.medianTimeToFixSeconds, prior: prior.medianTimeToFixSeconds)
                let connectionDrop = prior.connectionCount > 0
                    ? max(0, 1 - (Double(current.connectionCount) / Double(prior.connectionCount)))
                    : 0

                if gpsDrop >= 0.25 || (current.gpsFixCount == 0 && prior.gpsFixCount > 0) {
                    self.severity = .below
                    self.score = max(25, Int((gpsDrop * 100).rounded()))
                    self.summary = "GPS \(Self.formatPercent(current.gpsSuccessRate)) vs \(Self.formatPercent(prior.gpsSuccessRate)) · \(current.connectionCount) check-ins"
                } else if connectionDrop >= 0.50 {
                    self.severity = .below
                    self.score = max(25, Int((connectionDrop * 100).rounded()))
                    self.summary = "connections \(current.connectionCount) vs \(prior.connectionCount) · GPS \(Self.formatPercent(current.gpsSuccessRate))"
                } else if gpsDrop >= 0.10 || fixSlowdown >= 0.25 || connectionDrop >= 0.25 {
                    self.severity = .drift
                    self.score = max(10, Int((max(gpsDrop, fixSlowdown, connectionDrop) * 100).rounded()))
                    self.summary = "review threshold vs reference · \(current.gpsFixCount) GPS · \(current.connectionCount) check-ins"
                } else {
                    self.severity = .healthy
                    self.score = 0
                    self.summary = "within V0 threshold · \(current.gpsFixCount) GPS · \(current.connectionCount) check-ins"
                }
            } else {
                if current.connectionCount == 0 && current.gpsFixCount == 0 && current.fallbackFixCount == 0 {
                    self.severity = .below
                    self.score = 100
                    self.summary = "no telemetry in \(current.title.lowercased())"
                } else if current.gpsFixCount == 0 && current.fallbackFixCount > 0 {
                    self.severity = .below
                    self.score = 80
                    self.summary = "cell-locate-only locations · \(current.connectionCount) check-ins"
                } else if let gpsRate = current.gpsSuccessRate, gpsRate < 0.60 {
                    self.severity = .below
                    self.score = Int(((1 - gpsRate) * 100).rounded())
                    self.summary = "GPS \(Self.formatPercent(gpsRate)) · \(current.connectionCount) check-ins"
                } else if let gpsRate = current.gpsSuccessRate, gpsRate < 0.85 {
                    self.severity = .drift
                    self.score = Int(((1 - gpsRate) * 100).rounded())
                    self.summary = "GPS review · \(Self.formatPercent(gpsRate)) · \(current.connectionCount) check-ins"
                } else if let battery = current.medianBatteryVoltage, battery < 3.65 {
                    self.severity = .drift
                    self.score = 35
                    self.summary = "battery watch · \(Self.formatDetailValue(battery, as: .volts))"
                } else {
                    self.severity = .healthy
                    self.score = 0
                    self.summary = "no V0 screen hit · \(current.gpsFixCount) GPS · \(current.connectionCount) check-ins"
                }
            }
            return
        }

        let connectionAge = Self.daysAgo(device.latestConnectionAt)
        let locationAge = Self.daysAgo(device.latestLocationAt)
        self.sampledMapPoints = []

        if let connectionAge, connectionAge > 21 {
            severity = .below
            summary = "went dark \(connectionAge)d ago"
            score = nil
            segments = []
        } else if let locationAge, locationAge > 14 {
            severity = .below
            summary = "\(locationAge)-day GPS gap · investigate reception"
            score = nil
            segments = []
        } else if device.latestLocationAt == nil && device.latestConnectionAt != nil {
            severity = .fallback
            summary = "check-ins present · no GPS in project snapshot"
            score = nil
            segments = []
        } else if let locationAge, locationAge > 3 {
            severity = .drift
            summary = "GPS stale \(locationAge)d · still checking in"
            score = nil
            segments = []
        } else {
            severity = .healthy
            summary = "latest snapshot present · no analysis run"
            score = nil
            segments = []
        }
    }

    var verdict: String {
        if analysis == nil {
            switch severity {
            case .below: return "stale"
            case .drift: return "stale"
            case .fallback: return "snapshot"
            case .healthy: return "snapshot"
            }
        }
        switch severity {
        case .below: return "▼ \(score ?? 47)%"
        case .drift: return "review"
        case .fallback: return analysis == nil ? "insuf." : "current"
        case .healthy: return "within"
        }
    }

    var deviceFlagPill: String {
        if analysis == nil {
            return "SNAPSHOT · no analysis"
        }
        switch severity {
        case .below: return prior == nil ? "REVIEW THRESHOLD · current window" : "REVIEW THRESHOLD · \(primaryComparisonPill)"
        case .drift: return prior == nil ? "WATCH THRESHOLD · current window" : "WATCH THRESHOLD · \(primaryComparisonPill)"
        case .fallback: return analysis == nil ? "BASELINE · insufficient" : "CURRENT PERIOD"
        case .healthy: return prior == nil ? "CURRENT · no screen hit" : "NO V0 SCREEN HIT · vs reference"
        }
    }

    var gpsMetric: String {
        if let current {
            return Self.formatPercent(current.gpsSuccessRate)
        }
        return "—"
    }

    var gpsDelta: String {
        guard let current else { return "not analyzed" }
        guard let prior else {
            return current.gpsSuccessRate == nil ? "not exposed" : "current period"
        }
        guard current.gpsSuccessRate != nil else { return "current not exposed" }
        guard prior.gpsSuccessRate != nil else { return "reference not exposed" }
        return Self.formatPointDelta(current: current.gpsSuccessRate, prior: prior.gpsSuccessRate)
    }

    var fixDelta: String {
        guard let current else { return "not analyzed" }
        guard let currentSeconds = current.medianTimeToFixSeconds else {
            return "not exposed"
        }
        guard let prior else {
            return "current period"
        }
        guard let priorSeconds = prior.medianTimeToFixSeconds else {
            return "reference not exposed"
        }
        let delta = currentSeconds - priorSeconds
        if abs(delta) < 1 {
            return "≈ prior"
        }
        return "\(delta > 0 ? "▲" : "▼") \(Self.formatSeconds(abs(delta)))"
    }

    var fixTimeMetric: String {
        if let seconds = current?.medianTimeToFixSeconds {
            return Self.formatSeconds(seconds)
        }
        return "—"
    }

    var solarMetric: String {
        if let exposure = current?.solarExposureRate {
            return Self.formatPercent(exposure)
        }
        if let millivolts = current?.solarMillivolts {
            return "\(Int(millivolts.rounded()))mV"
        }
        return "—"
    }

    var solarDelta: String {
        guard let current else { return "not pulled" }
        guard let prior else {
            return hasSolarMetric(current) ? "current period" : "not exposed"
        }
        if let currentExposure = current.solarExposureRate {
            guard let priorExposure = prior.solarExposureRate else {
            return "reference not exposed"
            }
            return Self.formatPointDelta(current: currentExposure, prior: priorExposure)
        }
        if current.solarMillivolts != nil || current.solarMilliamps != nil {
            return "current exposed"
        }
        return "not exposed"
    }

    var connectionMetric: String {
        guard let current else { return "—" }
        return "\(current.connectionCount)"
    }

    var connectionDelta: String {
        guard let current else { return "not analyzed" }
        guard let prior else { return "current period" }
        guard prior.connectionCount > 0 else {
            return current.connectionCount == prior.connectionCount ? "≈ prior" : "\(current.connectionCount - prior.connectionCount)"
        }
        let delta = Double(current.connectionCount - prior.connectionCount) / Double(prior.connectionCount)
        if abs(delta) < 0.05 { return "≈ prior" }
        return "\(delta < 0 ? "▼" : "▲") \(Int(abs(delta * 100).rounded()))%"
    }

    var batteryMetric: String {
        if let battery = current?.medianBatteryVoltage {
            return String(format: "%.2fV", battery)
        }
        guard let battery = device.latestBatteryV else { return "—" }
        return String(format: "%.2fV", battery)
    }

    var batteryDelta: String {
        if let trend = current?.batteryTrendVoltsPerDay {
            return String(format: "%+.2f V/day", trend)
        }
        return device.latestBatteryV == nil ? "not exposed" : "snapshot only"
    }

    var activityMetric: String {
        guard let activity = current?.activityMean else { return "—" }
        if activity >= 100 {
            return "\(Int(activity.rounded()))"
        }
        return String(format: "%.1f", activity)
    }

    var lastFixText: String {
        if let days = Self.daysAgo(device.latestLocationAt) {
            return days == 0 ? "last fix today" : "last fix \(days)d ago"
        }
        return "no GPS fix in snapshot"
    }

    var windowCount: String {
        if let current {
            return "gps \(current.gpsFixCount) · conn \(current.connectionCount)"
        }
        return "not analyzed"
    }

    var hasComparison: Bool {
        prior != nil
    }

    var basisLabel: String {
        if analysis == nil {
            return "snapshot"
        }
        if prior != nil {
            return "vs reference"
        }
        return "current"
    }

    var hasGap: Bool {
        segments.contains { $0.kind == .gap }
    }

    var hasUsefulTimeline: Bool {
        segments.contains { $0.kind != .gap }
    }

    var hasFallback: Bool {
        segments.contains { $0.kind == .fallback }
    }

    var gapLabel: String {
        if summary.contains("day") {
            return summary.components(separatedBy: " · ").first ?? "gap"
        }
        return "gap"
    }

    var gpsBar: Double {
        if let rate = current?.gpsSuccessRate {
            return Self.clamped(rate)
        }
        return 0
    }

    var gpsPriorBar: Double {
        prior?.gpsSuccessRate.map(Self.clamped) ?? 0
    }

    var connectionBar: Double {
        guard let current else { return 0 }
        if let prior, prior.connectionCount > 0 {
            return Self.clamped(Double(current.connectionCount) / Double(prior.connectionCount))
        }
        return Self.clamped(Double(current.connectionCount) / 60)
    }

    var connectionPriorBar: Double {
        prior?.connectionCount == nil ? 0 : 1
    }

    var solarBar: Double {
        if let exposure = current?.solarExposureRate {
            return Self.clamped(exposure)
        }
        if let millivolts = current?.solarMillivolts {
            return Self.clamped(millivolts / 5_000)
        }
        if let milliamps = current?.solarMilliamps {
            return Self.clamped(milliamps / 200)
        }
        return 0
    }

    var solarPriorBar: Double {
        if let exposure = prior?.solarExposureRate {
            return Self.clamped(exposure)
        }
        if let millivolts = prior?.solarMillivolts {
            return Self.clamped(millivolts / 5_000)
        }
        if let milliamps = prior?.solarMilliamps {
            return Self.clamped(milliamps / 200)
        }
        return 0
    }

    var fixBar: Double {
        if let seconds = current?.medianTimeToFixSeconds {
            return Self.clamped(seconds / 120)
        }
        return 0
    }

    var fixPriorBar: Double {
        guard let seconds = prior?.medianTimeToFixSeconds else { return 0 }
        return Self.clamped(seconds / 120)
    }

    var batteryBar: Double {
        if let battery = current?.medianBatteryVoltage {
            return Self.clamped((battery - 3.3) / 1.0)
        }
        guard let battery = device.latestBatteryV else { return 0.50 }
        return Self.clamped((battery - 3.3) / 1.0)
    }

    var batteryPriorBar: Double {
        guard let battery = prior?.medianBatteryVoltage else { return 0 }
        return Self.clamped((battery - 3.3) / 1.0)
    }

    var activityBar: Double {
        guard let currentActivity = current?.activityMean else { return 0 }
        if let priorActivity = prior?.activityMean, priorActivity > 0 {
            return Self.clamped(currentActivity / priorActivity)
        }
        return Self.clamped(currentActivity / 100)
    }

    var activityPriorBar: Double {
        prior?.activityMean == nil ? 0 : 1
    }

    func rawMetricValue(for metric: DetailMetric) -> Double? {
        switch metric {
        case .gpsSuccess:
            return current?.gpsSuccessRate
        case .fixTime:
            return current?.medianTimeToFixSeconds
        case .connections:
            return current.map { Double($0.connectionCount) }
        case .solar:
            return current?.solarExposureRate ?? current?.solarMillivolts
        case .battery:
            return current?.medianBatteryVoltage ?? device.latestBatteryV
        case .activity:
            return current?.activityMean
        }
    }

    func priorMetricValue(for metric: DetailMetric) -> Double? {
        switch metric {
        case .gpsSuccess:
            return prior?.gpsSuccessRate
        case .fixTime:
            return prior?.medianTimeToFixSeconds
        case .connections:
            return prior.map { Double($0.connectionCount) }
        case .solar:
            return prior?.solarExposureRate ?? prior?.solarMillivolts
        case .battery:
            return prior?.medianBatteryVoltage
        case .activity:
            return prior?.activityMean
        }
    }

    func metricDisplay(for metric: DetailMetric) -> String {
        guard let value = rawMetricValue(for: metric) else { return "—" }
        return metric.formatRawValue(value)
    }

    func metricDeltaDisplay(for metric: DetailMetric) -> String {
        guard let current = rawMetricValue(for: metric) else { return "not exposed" }
        guard let prior = priorMetricValue(for: metric) else { return hasComparison ? "reference not exposed" : "current only" }

        switch metric {
        case .gpsSuccess, .solar:
            let points = (current - prior) * 100
            if abs(points) < 1 { return "≈ prior" }
            return "\(points < 0 ? "▼" : "▲") \(Int(abs(points).rounded())) pts"
        case .fixTime:
            let delta = current - prior
            if abs(delta) < 1 { return "≈ prior" }
            return "\(delta > 0 ? "▲" : "▼") \(Self.formatSeconds(abs(delta)))"
        case .connections, .activity:
            guard abs(prior) > 0.000_1 else { return current == prior ? "≈ prior" : "new signal" }
            let ratio = (current - prior) / abs(prior)
            if abs(ratio) < 0.05 { return "≈ prior" }
            return "\(ratio < 0 ? "▼" : "▲") \(Int(abs(ratio * 100).rounded()))%"
        case .battery:
            let delta = current - prior
            if abs(delta) < 0.02 { return "≈ prior" }
            return String(format: "%@%.2fV", delta < 0 ? "▼ " : "▲ ", abs(delta))
        }
    }

    func metricSortValue(for metric: DetailMetric) -> Double {
        guard let value = rawMetricValue(for: metric) else { return Double.greatestFiniteMagnitude }

        if let prior = priorMetricValue(for: metric), abs(prior) > 0.000_1 {
            let worseDelta = metric.lowerIsBetter
                ? (value - prior) / abs(prior)
                : (prior - value) / abs(prior)
            return -worseDelta
        }

        switch metric {
        case .fixTime:
            return -value
        case .connections, .gpsSuccess, .solar, .battery, .activity:
            return value
        }
    }

    func normalizedMetricValue(for metric: DetailMetric) -> Double {
        guard let value = rawMetricValue(for: metric) else { return 0 }
        switch metric {
        case .gpsSuccess, .solar:
            return Self.clamped(value)
        case .fixTime:
            return 1 - Self.clamped(value / 180)
        case .connections:
            return Self.clamped(value / 60)
        case .battery:
            return Self.clamped((value - 3.3) / 1.0)
        case .activity:
            return Self.clamped(value / 100)
        }
    }

    func normalizedPriorMetricValue(for metric: DetailMetric) -> Double {
        guard let value = priorMetricValue(for: metric) else { return 0 }
        switch metric {
        case .gpsSuccess, .solar:
            return Self.clamped(value)
        case .fixTime:
            return 1 - Self.clamped(value / 180)
        case .connections:
            return Self.clamped(value / 60)
        case .battery:
            return Self.clamped((value - 3.3) / 1.0)
        case .activity:
            return Self.clamped(value / 100)
        }
    }

    func cohortStatus(for metric: DetailMetric) -> CohortStatus {
        if let current = rawMetricValue(for: metric), let prior = priorMetricValue(for: metric) {
            return comparisonStatus(metric: metric, current: current, prior: prior)
        }

        switch metric {
        case .gpsSuccess:
            guard let rate = current?.gpsSuccessRate else { return .unknown("GPS not exposed") }
            if rate < 0.60 { return .bad("GPS low") }
            if rate < 0.85 { return .watch("GPS review") }
            return .good("no GPS screen hit")
        case .fixTime:
            guard let seconds = current?.medianTimeToFixSeconds else { return .unknown("TTF not exposed") }
            if seconds > 120 { return .bad("slow fix") }
            if seconds > 45 { return .watch("fix watch") }
            return .good("fast fix")
        case .connections:
            guard let count = current?.connectionCount else { return .unknown("not pulled") }
            if count == 0 { return .bad("went quiet") }
            if count < 8 { return .watch("few check-ins") }
            return .good("checking in")
        case .solar:
            guard let exposure = current?.solarExposureRate else {
                if current?.solarMillivolts != nil || current?.solarMilliamps != nil {
                    return .good("solar exposed")
                }
                return .unknown("solar not exposed")
            }
            if exposure <= 0 { return .watch("no solar exposure") }
            return .good("solar exposed")
        case .battery:
            guard let battery = current?.medianBatteryVoltage ?? device.latestBatteryV else { return .unknown("battery not exposed") }
            if battery < 3.55 { return .bad("battery low") }
            if battery < 3.75 { return .watch("battery watch") }
            return .good("battery within screen")
        case .activity:
            guard current?.activityMean != nil else { return .unknown("ACC not exposed") }
            return .good("activity value exposed")
        }
    }

    private func comparisonStatus(metric: DetailMetric, current: Double, prior: Double) -> CohortStatus {
        switch metric {
        case .gpsSuccess:
            let drop = Self.dropFraction(current: current, prior: prior)
            if drop >= 0.25 { return .bad("GPS flag") }
            if drop >= 0.10 { return .watch("GPS review") }
            return .good("within threshold")
        case .fixTime:
            let slowdown = Self.increaseFraction(current: current, prior: prior)
            if slowdown >= 0.50 { return .bad("slow fix") }
            if slowdown >= 0.25 { return .watch("fix review") }
            return .good("within threshold")
        case .connections:
            let drop = Self.dropFraction(current: current, prior: prior)
            if drop >= 0.50 { return .bad("went quiet") }
            if drop >= 0.25 { return .watch("check-in review") }
            return .good("within threshold")
        case .solar:
            let drop = Self.dropFraction(current: current, prior: prior)
            if drop >= 0.50 { return .watch("solar drop") }
            return current <= 0 ? .watch("no solar") : .good("within threshold")
        case .battery:
            let delta = current - prior
            if current < 3.55 { return .bad("battery low") }
            if delta < -0.15 || current < 3.75 { return .watch("battery watch") }
            return .good("within threshold")
        case .activity:
            guard abs(prior) > 0.000_1 else { return .good("activity value exposed") }
            let ratio = (current - prior) / abs(prior)
            if abs(ratio) >= 0.50 { return .watch("activity shift") }
            return .good("within threshold")
        }
    }

    var connectionBuckets: [DeviceLifelineBucket] {
        analysis?.lifelineBuckets ?? []
    }

    var timelineLabels: [String] {
        let buckets = connectionBuckets
        guard let first = buckets.first?.startDate,
              let last = buckets.last?.endDate,
              first < last
        else {
            if let current {
                return Self.timelineLabels(start: current.startDate, end: current.endDate)
            }
            return []
        }
        return Self.timelineLabels(start: first, end: last)
    }

    var activityDelta: String {
        guard let currentActivity = current?.activityMean else { return "not exposed" }
        guard let prior else { return "current period" }
        guard let priorActivity = prior.activityMean, priorActivity > 0 else { return "reference not exposed" }
        let delta = (currentActivity - priorActivity) / priorActivity
        if abs(delta) < 0.05 { return "≈ prior" }
        return "\(delta < 0 ? "▼" : "▲") \(Int(abs(delta * 100).rounded()))%"
    }

    var metricWindowLabel: String {
        guard let current else { return "no completed run" }
        var label = "\(current.title): \(Formatters.shortDateTime.string(from: current.startDate)) → \(Formatters.shortDateTime.string(from: current.endDate))"
        if let prior {
            label += " · \(prior.title): \(Formatters.shortDateTime.string(from: prior.startDate)) → \(Formatters.shortDateTime.string(from: prior.endDate))"
        }
        return label
    }

    var readText: String {
        if let current {
            if let prior {
                let gpsPhrase = "GPS \(gpsMetric) (\(gpsDelta))"
                let connectionPhrase = "check-ins \(current.connectionCount) vs \(prior.connectionCount) (\(connectionDelta))"
                let activityPhrase = activityDelta == "not exposed" ? nil : "activity \(activityDelta)"

                switch severity {
                case .below:
                    return "This run crossed a V0 review threshold. Main driver: \(primaryPerformanceDriver). \(gpsPhrase); \(connectionPhrase).\(activityPhrase.map { " \($0)." } ?? "")"
                case .drift:
                    return "This run crossed a watch threshold, not a validated failure test. Main driver: \(primaryPerformanceDriver). \(gpsPhrase); \(connectionPhrase).\(activityPhrase.map { " \($0)." } ?? "")"
                case .fallback:
                    return "Telemetry was pulled, but this device does not have enough comparable reference-window data for a strong screen. Current window: \(current.gpsFixCount) GPS fixes and \(current.connectionCount) check-ins."
                case .healthy:
                    return "No V0 screening threshold was crossed in the compared windows. \(gpsPhrase); \(connectionPhrase). Inspect individual metrics before ruling out a field complaint."
                }
            }

            switch severity {
            case .below:
                return "Current-period screen ranks this transmitter first: \(primaryCurrentHealthDriver). Window totals: \(current.gpsFixCount) GPS fixes, \(current.fallbackFixCount) non-GPS location fixes, and \(current.connectionCount) check-ins."
            case .drift:
                return "Current-period screen marks this transmitter for review: \(primaryCurrentHealthDriver). It is not a decline claim; it is an absolute screen for this run window."
            case .fallback:
                return "Telemetry was pulled for this transmitter. The run has one current window, so the read is based on absolute values rather than a before/after comparison."
            case .healthy:
                return "No current-period V0 screen was hit for this transmitter: \(current.gpsFixCount) GPS fixes, \(current.connectionCount) check-ins, and \(batteryMetric) battery."
            }
        }

        return "No completed analysis run covers this visible scope. Snapshot fields can show last connection or last fix age, but performance metrics need a run."
    }

    var mapPoints: [MapPoint] {
        if !sampledMapPoints.isEmpty {
            return sampledMapPoints
        }
        return []
    }

    var hasBatteryTrace: Bool {
        analysis?.batteryPoints != nil
    }

    var currentBatteryPoints: [DeviceBatteryPoint] {
        guard let points = analysis?.batteryPoints else { return [] }
        guard let current else { return points }
        let interval = DateInterval(start: current.startDate, end: current.endDate)
        return points.filter { interval.contains($0.timestamp) }
    }

    var batteryRechargeSummary: BatteryRechargeSummary {
        MetricCalculator().batteryRechargeSummary(points: currentBatteryPoints)
    }

    func verdictColor(_ scheme: ColorScheme) -> Color {
        switch severity {
        case .below: return CTTColor.vermilion(scheme)
        case .drift: return CTTColor.ochre(scheme)
        case .fallback: return CTTColor.fallback(scheme)
        case .healthy: return CTTColor.green(scheme)
        }
    }

    func basisColor(_ scheme: ColorScheme) -> Color {
        if analysis == nil {
            return CTTColor.fg3(scheme)
        }
        if prior != nil {
            return CTTColor.accent(scheme)
        }
        return CTTColor.fallback(scheme)
    }

    func gpsColor(_ scheme: ColorScheme) -> Color {
        let drop = Self.dropFraction(current: current?.gpsSuccessRate, prior: prior?.gpsSuccessRate)
        if drop >= 0.25 { return CTTColor.vermilion(scheme) }
        if drop >= 0.10 { return CTTColor.ochre(scheme) }
        guard current?.gpsSuccessRate != nil else { return CTTColor.fg3(scheme) }
        return CTTColor.green(scheme)
    }

    func fixColor(_ scheme: ColorScheme) -> Color {
        guard current?.medianTimeToFixSeconds != nil else { return CTTColor.fg3(scheme) }
        let slowdown = Self.increaseFraction(current: current?.medianTimeToFixSeconds, prior: prior?.medianTimeToFixSeconds)
        if slowdown >= 0.50 {
            return CTTColor.vermilion(scheme)
        }
        if slowdown >= 0.25 {
            return CTTColor.ochre(scheme)
        }
        return CTTColor.green(scheme)
    }

    func connectionColor(_ scheme: ColorScheme) -> Color {
        let drop = connectionDropFraction
        if drop >= 0.50 { return CTTColor.vermilion(scheme) }
        if drop >= 0.25 { return CTTColor.ochre(scheme) }
        guard current != nil else { return CTTColor.fg3(scheme) }
        return CTTColor.green(scheme)
    }

    func solarColor(_ scheme: ColorScheme) -> Color {
        guard let current else { return CTTColor.fg3(scheme) }
        if let exposure = current.solarExposureRate {
            return exposure <= 0 ? CTTColor.ochre(scheme) : CTTColor.green(scheme)
        }
        if current.solarMillivolts != nil || current.solarMilliamps != nil {
            return CTTColor.green(scheme)
        }
        return CTTColor.fg3(scheme)
    }

    func activityColor(_ scheme: ColorScheme) -> Color {
        let drop = activityDropFraction
        if drop >= 0.50 { return CTTColor.accent(scheme) }
        if drop >= 0.25 { return CTTColor.ochre(scheme) }
        guard current?.activityMean != nil else { return CTTColor.fg3(scheme) }
        return CTTColor.green(scheme)
    }

    func batteryColor(_ scheme: ColorScheme) -> Color {
        if let trend = current?.batteryTrendVoltsPerDay, trend < -0.05 {
            return CTTColor.ochre(scheme)
        }
        if let battery = current?.medianBatteryVoltage {
            return battery < 3.7 ? CTTColor.ochre(scheme) : CTTColor.green(scheme)
        }
        guard let battery = device.latestBatteryV else { return CTTColor.fg3(scheme) }
        return battery < 3.7 ? CTTColor.ochre(scheme) : CTTColor.green(scheme)
    }

    private func hasSolarMetric(_ metrics: DeviceWindowMetrics) -> Bool {
        metrics.solarExposureRate != nil
            || metrics.solarMillivolts != nil
            || metrics.solarMilliamps != nil
    }

    func detailRow(_ label: String, current: Int?, prior: Int?, format: MetricDetailFormat) -> MetricDetailRow {
        detailRow(label, current: current.map(Double.init), prior: prior.map(Double.init), format: format)
    }

    func detailRow(_ label: String, current: Double?, prior: Double?, format: MetricDetailFormat) -> MetricDetailRow {
        let currentText = Self.formatDetailValue(current, as: format)
        let priorText = Self.formatDetailValue(prior, as: format)
        let change = Self.formatDetailChange(current: current, prior: prior, as: format)
        return MetricDetailRow(
            label: label,
            current: currentText,
            prior: prior == nil && current != nil ? "current summary" : priorText,
            change: change.text,
            isImportant: change.isImportant,
            currentBar: Self.normalizedDetailValue(current, prior: prior, as: format),
            priorBar: Self.normalizedDetailValue(prior, prior: current, as: format)
        )
    }

    static func < (lhs: DeviceDiagnostic, rhs: DeviceDiagnostic) -> Bool {
        if lhs.severity.rank != rhs.severity.rank {
            return lhs.severity.rank < rhs.severity.rank
        }
        return lhs.device.displayName.localizedCaseInsensitiveCompare(rhs.device.displayName) == .orderedAscending
    }

    static func == (lhs: DeviceDiagnostic, rhs: DeviceDiagnostic) -> Bool {
        lhs.id == rhs.id
    }

    private static func daysAgo(_ value: String?) -> Int? {
        guard let value, let date = try? TimestampNormalizer.parseISO8601(value) else { return nil }
        let interval = max(0, Date().timeIntervalSince(date))
        return Int(interval / 86_400)
    }

    private static func currentWindow(from windows: [DeviceWindowMetrics]) -> DeviceWindowMetrics? {
        windows.first { ["primary", "recent", "period", "all"].contains($0.id) } ?? windows.first
    }

    private static func priorWindow(from windows: [DeviceWindowMetrics]) -> DeviceWindowMetrics? {
        windows.first { $0.id == "comparison" } ?? windows.dropFirst().first
    }

    private static func segments(from buckets: [DeviceLifelineBucket]) -> [LifelineSegment] {
        guard !buckets.isEmpty else { return [.gap(0, 1)] }
        var result: [LifelineSegment] = []
        let width = 1 / Double(buckets.count)

        for (index, bucket) in buckets.enumerated() {
            let kind: LifelineSegment.Kind
            if bucket.gpsFixCount > 0 {
                kind = .gps
            } else if bucket.fallbackFixCount > 0 {
                kind = .fallback
            } else {
                kind = .gap
            }

            if let last = result.last, last.kind == kind {
                result[result.count - 1] = LifelineSegment(kind: kind, start: last.start, width: last.width + width)
            } else {
                result.append(LifelineSegment(kind: kind, start: Double(index) * width, width: width))
            }
        }

        return result
    }

    private static func mapPoints(from fixPoints: [DeviceFixPoint]) -> [MapPoint] {
        fixPoints.map { point in
            MapPoint(
                id: point.id,
                timestamp: point.timestamp,
                lat: point.lat,
                lon: point.lon,
                isFallback: point.isFallback,
                type: point.type,
                timeToFix: point.timeToFix,
                hdop: point.hdop,
                satCount: point.satCount,
                uncertaintyM: point.uncertaintyM
            )
        }
    }

    private static func dropFraction(current: Double?, prior: Double?) -> Double {
        guard let current, let prior, prior > 0 else { return 0 }
        return max(0, (prior - current) / prior)
    }

    private static func increaseFraction(current: Double?, prior: Double?) -> Double {
        guard let current, let prior, prior > 0 else { return 0 }
        return max(0, (current - prior) / prior)
    }

    private static func formatPercent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private static func formatSeconds(_ value: Double) -> String {
        if value >= 60 {
            return "\(Int(value.rounded()))s"
        }
        return "\(Int(value.rounded()))s"
    }

    private static func formatPointDelta(current: Double?, prior: Double?) -> String {
        guard let current, let prior else { return "not exposed" }
        let points = (current - prior) * 100
        if abs(points) < 1 { return "≈ prior" }
        return "\(points < 0 ? "▼" : "▲") \(Int(abs(points).rounded())) pts"
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private static func timelineLabels(start: Date, end: Date) -> [String] {
        let count = 4
        let duration = max(1, end.timeIntervalSince(start))
        let formatter = DateFormatter()
        if Calendar.current.component(.year, from: start) == Calendar.current.component(.year, from: end) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yy"
        }

        return (0..<count).map { index in
            let fraction = Double(index) / Double(count - 1)
            return formatter.string(from: start.addingTimeInterval(duration * fraction))
        }
    }

    private var connectionDropFraction: Double {
        guard let current, let prior, prior.connectionCount > 0 else { return 0 }
        return max(0, 1 - (Double(current.connectionCount) / Double(prior.connectionCount)))
    }

    private var activityDropFraction: Double {
        guard let current = current?.activityMean,
              let prior = prior?.activityMean,
              prior > 0
        else {
            return 0
        }
        return max(0, 1 - (current / prior))
    }

    private var primaryPerformanceDriver: String {
        let gpsDrop = Self.dropFraction(current: current?.gpsSuccessRate, prior: prior?.gpsSuccessRate)
        let fixSlowdown = Self.increaseFraction(current: current?.medianTimeToFixSeconds, prior: prior?.medianTimeToFixSeconds)
        let connectionDrop = connectionDropFraction

        let drivers = [
            ("GPS fix yield", gpsDrop, gpsDrop >= 0.01 ? "\(Int((gpsDrop * 100).rounded()))% lower than prior" : "near prior"),
            ("fix time", fixSlowdown, fixSlowdown >= 0.01 ? "\(Int((fixSlowdown * 100).rounded()))% slower than prior" : "near prior"),
            ("check-ins", connectionDrop, connectionDrop >= 0.01 ? "\(Int((connectionDrop * 100).rounded()))% fewer than prior" : "near prior")
        ]

        let driver = drivers.max { lhs, rhs in lhs.1 < rhs.1 } ?? drivers[0]
        if driver.1 < 0.05 {
            return "no GPS, fix-time, or connection metric crossed the current review threshold"
        }
        return "\(driver.0) \(driver.2)"
    }

    private var primaryComparisonPill: String {
        guard let current else { return "not analyzed" }
        if current.connectionCount == 0 && current.gpsFixCount == 0 && current.fallbackFixCount == 0 {
            return "no telemetry in current window"
        }

        let gpsDrop = Self.dropFraction(current: current.gpsSuccessRate, prior: prior?.gpsSuccessRate)
        let fixSlowdown = Self.increaseFraction(current: current.medianTimeToFixSeconds, prior: prior?.medianTimeToFixSeconds)
        let connectionDrop = connectionDropFraction

        if gpsDrop >= fixSlowdown && gpsDrop >= connectionDrop && gpsDrop >= 0.05 {
            return "GPS \(gpsDelta) vs reference"
        }
        if fixSlowdown >= gpsDrop && fixSlowdown >= connectionDrop && fixSlowdown >= 0.05 {
            return "fix \(fixDelta) vs reference"
        }
        if connectionDrop >= 0.05 {
            return "check-ins \(connectionDelta) vs reference"
        }
        return "within threshold vs reference"
    }

    private var primaryCurrentHealthDriver: String {
        let candidates = DetailMetric.allCases
            .map { metric in (metric.title, cohortStatus(for: metric)) }
            .filter { $0.1.isProblem }

        if let bad = candidates.first(where: {
            if case .bad = $0.1 { return true }
            return false
        }) {
            return "\(bad.0) \(bad.1.text.lowercased())"
        }

        if let watch = candidates.first {
            return "\(watch.0) \(watch.1.text.lowercased())"
        }

        return "no absolute metric crossed the current screening thresholds"
    }

    private static func formatDetailValue(_ value: Double?, as format: MetricDetailFormat) -> String {
        guard let value else { return "—" }
        switch format {
        case .count:
            return "\(Int(value.rounded()))"
        case .decimal:
            return value >= 100 ? "\(Int(value.rounded()))" : String(format: "%.2f", value)
        case .percentPoints:
            return "\(Int((value * 100).rounded()))%"
        case .seconds:
            return String(format: "%.0fs", value)
        case .hours:
            return value >= 24 ? String(format: "%.1fd", value / 24) : String(format: "%.1fh", value)
        case .volts:
            return String(format: "%.2f V", value)
        case .voltsPerDay:
            return String(format: "%+.3f V/day", value)
        case .millivolts:
            return "\(Int(value.rounded())) mV"
        case .milliamps:
            return "\(Int(value.rounded())) mA"
        case .celsius:
            return String(format: "%.1f C", value)
        }
    }

    private static func formatDetailChange(current: Double?, prior: Double?, as format: MetricDetailFormat) -> (text: String, isImportant: Bool) {
        guard let current, let prior else { return ("—", false) }
        switch format {
        case .percentPoints:
            let points = (current - prior) * 100
            if abs(points) < 1 { return ("≈ prior", false) }
            return ("\(points < 0 ? "▼" : "▲") \(Int(abs(points).rounded())) pts", abs(points) >= 10)
        case .count, .decimal, .seconds, .hours, .volts, .voltsPerDay, .millivolts, .milliamps, .celsius:
            let delta = current - prior
            if abs(delta) < 0.000_1 { return ("≈ prior", false) }
            if abs(prior) > 0.000_1 {
                let ratio = delta / abs(prior)
                if abs(ratio) >= 0.05 {
                    return ("\(ratio < 0 ? "▼" : "▲") \(Int(abs(ratio * 100).rounded()))%", abs(ratio) >= 0.25)
                }
            }
            return (delta < 0 ? "▼" : "▲", false)
        }
    }

    private static func normalizedDetailValue(_ value: Double?, prior: Double?, as format: MetricDetailFormat) -> Double {
        guard let value else { return 0 }
        switch format {
        case .percentPoints:
            return clamped(value)
        case .seconds:
            return clamped(value / 180)
        case .hours:
            return clamped(value / 48)
        case .volts:
            return clamped((value - 3.3) / 1.0)
        case .voltsPerDay:
            return clamped((value + 0.10) / 0.20)
        case .millivolts:
            return clamped(value / 6_000)
        case .milliamps:
            return clamped(value / 25)
        case .celsius:
            return clamped((value + 10) / 60)
        case .count, .decimal:
            let reference = max(abs(value), abs(prior ?? 0), 1)
            return clamped(abs(value) / reference)
        }
    }
}

private enum CohortStatus {
    case good(String)
    case watch(String)
    case bad(String)
    case unknown(String)

    var text: String {
        switch self {
        case let .good(text), let .watch(text), let .bad(text), let .unknown(text):
            return text
        }
    }

    var isProblem: Bool {
        switch self {
        case .bad, .watch:
            return true
        case .good, .unknown:
            return false
        }
    }

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .good:
            return CTTColor.green(scheme)
        case .watch:
            return CTTColor.ochre(scheme)
        case .bad:
            return CTTColor.vermilion(scheme)
        case .unknown:
            return CTTColor.fg3(scheme)
        }
    }
}

private enum Severity {
    case below
    case drift
    case fallback
    case healthy

    var rank: Int {
        switch self {
        case .below: return 0
        case .drift: return 1
        case .fallback: return 2
        case .healthy: return 3
        }
    }
}

private struct LifelineSegment: Identifiable {
    enum Kind { case gps, fallback, gap }

    let id = UUID()
    let kind: Kind
    let start: Double
    let width: Double

    static func gps(_ start: Double, _ width: Double) -> LifelineSegment {
        LifelineSegment(kind: .gps, start: start, width: width)
    }

    static func fallback(_ start: Double, _ width: Double) -> LifelineSegment {
        LifelineSegment(kind: .fallback, start: start, width: width)
    }

    static func gap(_ start: Double, _ width: Double) -> LifelineSegment {
        LifelineSegment(kind: .gap, start: start, width: width)
    }
}

private struct MapPoint: Identifiable {
    let id: Int
    let timestamp: Date
    let lat: Double
    let lon: Double
    let isFallback: Bool
    let type: LocationKind?
    let timeToFix: Int?
    let hdop: Double?
    let satCount: Int?
    let uncertaintyM: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var typeLabel: String {
        if type == .cellLocate {
            return "cell-locate"
        }
        return type?.rawValue.replacingOccurrences(of: "_", with: "-") ?? (isFallback ? "cell-locate" : "gps")
    }

    var annotationTitle: String {
        "\(typeLabel) · \(Formatters.shortDateTime.string(from: timestamp))"
    }
}
