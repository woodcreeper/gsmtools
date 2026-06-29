import AppKit
import GSMToolsCore
import SwiftUI

private enum ProjectBrowserLayout {
    static let paneMinHeight: CGFloat = 390
}

struct ProjectBrowserView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HeaderView(
                title: "Projects",
                subtitle: "Use this screen to build cohorts. Analysis starts from Runs; Devices shows the resulting lifelines.",
                infoBullets: [
                    "Load projects from the current API token.",
                    "Choose a project, load devices, then select transmitters.",
                    "Create a cohort when the same transmitter set will be analyzed more than once.",
                    "Open Runs to choose the question and data window."
                ]
            )

            ProjectFlowStrip()

            HStack(spacing: 8) {
                Button {
                    Task { await model.refreshAccount() }
                } label: {
                    LoadingLabel(
                        title: "Load Projects",
                        systemImage: "arrow.clockwise",
                        isLoading: model.loadingActivity == "Refreshing account"
                    )
                }
                .disabled(model.isLoading)

                Button {
                    Task { await model.loadDevicesForSelectedProject() }
                } label: {
                    LoadingLabel(
                        title: "Load Devices",
                        systemImage: "antenna.radiowaves.left.and.right",
                        isLoading: model.loadingActivity == "Loading devices"
                    )
                }
                .disabled(model.selectedProjectId == nil || model.isLoading)

                Button {
                    Task { await model.loadSampleLocations() }
                } label: {
                    LoadingLabel(
                        title: "Sample Locations",
                        systemImage: "location.magnifyingglass",
                        isLoading: model.loadingActivity == "Loading sample locations"
                    )
                }
                .disabled(model.isLoading)

                Spacer()

                Button {
                    model.requestedSection = .runs
                } label: {
                    Label("Open Runs", systemImage: "play.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(CTTColor.accent(scheme))
            }
            .controlSize(.regular)

            CohortCreationBar()

            HSplitView {
                ProjectListPane()
                    .frame(minWidth: 300, idealWidth: 330)
                DeviceListPane()
                    .frame(minWidth: 420)
                RawLocationPane()
                    .frame(minWidth: 380)
            }
        }
        .padding(18)
        .background(CTTColor.canvas(scheme))
    }
}

private struct ProjectFlowStrip: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 8) {
            FlowChip(number: 1, title: "Load account")
            FlowChip(number: 2, title: "Choose project")
            FlowChip(number: 3, title: "Select devices")
            FlowChip(number: 4, title: "Create cohort")
            FlowChip(number: 5, title: "Run analysis")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cttCard()
    }
}

private struct FlowChip: View {
    @Environment(\.colorScheme) private var scheme
    let number: Int
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(CTTColor.accent(scheme))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CTTColor.fg2(scheme))
                .lineLimit(1)
        }
    }
}

private struct SearchField: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CTTColor.fg3(scheme))
                .frame(width: 14)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
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
        .background(CTTColor.panel(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }
}

private struct CohortCreationBar: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cohort")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(CTTColor.accent(scheme))
                Text("\(model.selectedIMEIs.count) selected · \(model.selectedProjectSummary)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
            }

            TextField("Name this device group", text: $model.newTestGroupName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)

            Button {
                model.createTestGroupFromSelection()
            } label: {
                Label("Create Group", systemImage: "plus.circle")
            }
            .disabled(model.selectedIMEIs.isEmpty)

            Button {
                model.selectedIMEIs = []
                model.updateEstimate()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .disabled(model.selectedIMEIs.isEmpty)

            Spacer()
        }
        .padding(12)
        .cttCard()
    }
}

private struct ProjectListPane: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var projects: [ProjectListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.projects }
        return model.projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || project.projectId.localizedCaseInsensitiveContains(query)
                || (project.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PaneHeader(
                title: "Projects",
                detail: "\(projects.count) of \(model.projects.count) visible",
                info: "Projects are discovered from the API key. Admin keys may see many projects; customer keys may only see projects their account can access."
            )

            SearchField(text: $searchText, prompt: "Search projects")

            if model.loadingActivity == "Refreshing account", model.projects.isEmpty {
                LoadingStateView(title: "Loading projects", detail: model.statusMessage, systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.projects.isEmpty {
                ContentUnavailableView("No projects loaded", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.isEmpty {
                ContentUnavailableView("No matching projects", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projects) { project in
                            Button {
                                Task { await model.selectProject(project.projectId, loadDevices: true) }
                            } label: {
                                ProjectRow(
                                    project: project,
                                    isSelected: model.selectedProjectId == project.projectId,
                                    selectedCount: model.selectedDeviceCount(in: project.projectId)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text(model.selectedProject?.name ?? "No project selected")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CTTColor.fg3(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(minHeight: ProjectBrowserLayout.paneMinHeight, maxHeight: .infinity, alignment: .top)
        .cttCard()
    }
}

private struct ProjectRow: View {
    @Environment(\.colorScheme) private var scheme
    let project: ProjectListItem
    let isSelected: Bool
    let selectedCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? CTTColor.accent(scheme) : CTTColor.fg3(scheme))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.system(size: 14, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(CTTColor.ink(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(project.projectId)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if selectedCount > 0 {
                Text("\(selectedCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(CTTColor.accent(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .help("\(selectedCount) selected from this project")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? CTTColor.rowSelected(scheme) : CTTColor.paper(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
        }
        .contentShape(Rectangle())
    }
}

private struct DeviceListPane: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @State private var selectionAnchorIMEI: String?
    @State private var searchText = ""

    private var devices: [ProjectDeviceListItem] {
        let sorted = model.sortedSelectedProjectDevices
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { device in
            device.displayName.localizedCaseInsensitiveContains(query)
                || device.imei.localizedCaseInsensitiveContains(query)
                || device.deviceType.localizedCaseInsensitiveContains(query)
        }
    }

    private var currentProjectSelectedCount: Int {
        guard let projectId = model.selectedProjectId else { return 0 }
        return model.selectedDeviceCount(in: projectId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                PaneHeader(
                    title: "Devices",
                    detail: "\(devices.count) of \(model.selectedProjectDevices.count) loaded · \(currentProjectSelectedCount) here · \(model.selectedIMEIs.count) total",
                    info: "Use search and sorting to find transmitters, then select devices to create a cohort or run analysis. Shift-click selects a contiguous range."
                )
                Spacer()
                Picker("Sort", selection: $model.deviceSortMode) {
                    ForEach(DeviceSortMode.allCases) { mode in
                        Text(mode.fullTitle).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }

            SearchField(text: $searchText, prompt: "Search devices")

            HStack {
                Text("Sort: \(model.deviceSortMode.fullTitle)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                Spacer()
                Button {
                    selectAllVisibleDevices()
                } label: {
                    Label("Select All", systemImage: "checkmark.circle")
                }
                .disabled(devices.isEmpty)

                Button {
                    deselectAllVisibleDevices()
                } label: {
                    Label("Deselect All", systemImage: "circle")
                }
                .disabled(devices.isEmpty || !hasVisibleSelection)

                Button {
                    Task { await model.loadConnectionCountsForSelectedProject() }
                } label: {
                    LoadingLabel(
                        title: "Counts",
                        systemImage: "number",
                        isLoading: model.loadingActivity == "Loading connection counts"
                    )
                }
                .disabled(model.selectedProjectDevices.isEmpty || model.isLoading)
                InfoPopoverButton(
                    title: "Connection counts",
                    message: "Counts loads recent check-in totals for the devices in this project so you can sort by most connections before creating a cohort.",
                    width: 320
                )
            }

            if model.loadingActivity == "Loading devices", model.selectedProjectDevices.isEmpty {
                LoadingStateView(title: "Loading devices", detail: model.statusMessage, systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if devices.isEmpty {
                ContentUnavailableView(
                    model.selectedProjectDevices.isEmpty ? "No devices loaded" : "No matching devices",
                    systemImage: model.selectedProjectDevices.isEmpty ? "antenna.radiowaves.left.and.right" : "magnifyingglass"
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(devices) { device in
                            Button {
                                select(device, from: devices)
                            } label: {
                                DeviceRow(
                                    device: device,
                                    isSelected: model.selectedIMEIs.contains(device.imei),
                                    connectionCount: model.connectionCountsByIMEI[device.imei]
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Text("\(model.selectedIMEIs.count) selected across \(model.selectedProjectSummary)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CTTColor.fg3(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .onChange(of: model.selectedProjectId) { _, _ in
            selectionAnchorIMEI = nil
        }
        .padding(12)
        .frame(minHeight: ProjectBrowserLayout.paneMinHeight, maxHeight: .infinity, alignment: .top)
        .cttCard()
    }

    private func select(_ device: ProjectDeviceListItem, from visibleDevices: [ProjectDeviceListItem]) {
        if isShiftClick,
           let anchorIMEI = selectionAnchorIMEI,
           let anchorIndex = visibleDevices.firstIndex(where: { $0.imei == anchorIMEI }),
           let targetIndex = visibleDevices.firstIndex(where: { $0.imei == device.imei }) {
            let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            for visibleDevice in visibleDevices[bounds] {
                model.selectedIMEIs.insert(visibleDevice.imei)
            }
        } else {
            toggle(device.imei)
            selectionAnchorIMEI = device.imei
        }

        model.updateEstimate()
    }

    private var hasVisibleSelection: Bool {
        devices.contains { model.selectedIMEIs.contains($0.imei) }
    }

    private func selectAllVisibleDevices() {
        for device in devices {
            model.selectedIMEIs.insert(device.imei)
        }
        selectionAnchorIMEI = devices.last?.imei
        model.updateEstimate()
    }

    private func deselectAllVisibleDevices() {
        for device in devices {
            model.selectedIMEIs.remove(device.imei)
        }
        selectionAnchorIMEI = nil
        model.updateEstimate()
    }

    private var isShiftClick: Bool {
        guard let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) else {
            return false
        }
        return flags.contains(.shift)
    }

    private func toggle(_ imei: String) {
        if model.selectedIMEIs.contains(imei) {
            model.selectedIMEIs.remove(imei)
        } else {
            model.selectedIMEIs.insert(imei)
        }
    }
}

private struct DeviceRow: View {
    @Environment(\.colorScheme) private var scheme
    let device: ProjectDeviceListItem
    let isSelected: Bool
    let connectionCount: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? CTTColor.accent(scheme) : CTTColor.fg3(scheme))
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CTTColor.ink(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(device.deviceType)
                        .font(.system(size: 12))
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .lineLimit(1)
                }
                Text(device.imei)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg2(scheme))
                Text(metadata)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(metadataHelp)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(isSelected ? CTTColor.rowSelected(scheme) : CTTColor.paper(scheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CTTColor.line2(scheme)).frame(height: 1)
        }
        .contentShape(Rectangle())
    }

    private var metadata: String {
        var parts = [
            "Conn \(formattedTimestamp(device.latestConnectionAt) ?? "none")",
            latestFixText
        ]
        if let connectionCount {
            parts.append("\(connectionCount) check-ins")
        }
        if let battery = device.latestBatteryV {
            parts.append(String(format: "%.2f V", battery))
        }
        return parts.joined(separator: " · ")
    }

    private var latestFixText: String {
        if let timestamp = formattedTimestamp(device.latestLocationAt) {
            return "Latest fix \(timestamp)"
        }
        return "GPS not in snapshot"
    }

    private var metadataHelp: String {
        var lines = [
            "This row uses the project/device snapshot endpoint.",
            "Conn is the latest connection timestamp exposed in that snapshot."
        ]
        if device.latestLocationAt == nil {
            lines.append("GPS not in snapshot means latestLocationAt was not provided here; it does not prove the device has no GPS telemetry.")
        } else {
            lines.append("Latest fix is the latest location timestamp exposed in this snapshot.")
        }
        lines.append("Run analysis or pull samples to inspect actual telemetry records.")
        return lines.joined(separator: "\n")
    }

    private func formattedTimestamp(_ value: String?) -> String? {
        guard let value,
              let date = try? TimestampNormalizer.parseISO8601(value)
        else {
            return nil
        }
        return Formatters.shortDateTime.string(from: date)
    }
}

private struct RawLocationPane: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @State private var sortOrder = [KeyPathComparator(\SampleLocationRow.timestamp)]

    private var sortedLocations: [SampleLocationRow] {
        model.sampleLocationRows.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            PaneHeader(
                title: "Sample locations",
                detail: model.sampleLocationTargetDescription ?? "No sample pulled",
                info: "Sample locations is a quick API sanity check for one transmitter. Sort the table headers to inspect returned fixes; full analysis happens from Runs."
            )

            if model.loadingActivity == "Loading sample locations" {
                LoadingStateView(title: "Loading sample locations", detail: model.statusMessage, systemImage: "location.magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sortedLocations.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView("No sample pulled", systemImage: "location.magnifyingglass")
                    Button {
                        Task { await model.loadSampleLocations() }
                    } label: {
                        Label("Pull Sample", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.isLoading)
                    Text("Samples are pulled on demand for selected transmitters. With no selection, the app uses one transmitter with known locations in the selected project.")
                        .font(.system(size: 12))
                        .foregroundStyle(CTTColor.fg3(scheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(sortedLocations, sortOrder: $sortOrder) {
                    TableColumn("Unit", value: \.unitLabel) { row in
                        Text(row.unitLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn("Project", value: \.projectName) { row in
                        Text(row.projectName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    TableColumn("Fix", value: \.timestamp) { row in
                        Text(Formatters.shortDateTime.string(from: row.timestamp))
                    }
                    TableColumn("Type", value: \.typeRawValue) { row in
                        Text(row.typeRawValue)
                    }
                    TableColumn("Lat", value: \.sortableLatitude) { row in
                        Text(row.location.lat.map { String(format: "%.5f", $0) } ?? "-")
                    }
                    TableColumn("Lon", value: \.sortableLongitude) { row in
                        Text(row.location.lon.map { String(format: "%.5f", $0) } ?? "-")
                    }
                    TableColumn("TTF", value: \.sortableTimeToFix) { row in
                        Text(row.location.timeToFix.map { "\($0)s" } ?? "-")
                    }
                }
            }
        }
        .padding(12)
        .frame(minHeight: ProjectBrowserLayout.paneMinHeight, maxHeight: .infinity, alignment: .top)
        .cttCard()
    }
}

private struct PaneHeader: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let detail: String
    var info: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                if let info {
                    InfoPopoverButton(title: title, message: info)
                }
            }
            Text(detail)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(CTTColor.fg3(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct LoadingLabel: View {
    let title: String
    let systemImage: String
    let isLoading: Bool

    var body: some View {
        if isLoading {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

private struct LoadingStateView: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(CTTColor.fg3(scheme))
            ProgressView()
                .controlSize(.regular)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))
                Text(detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        }
        .padding(18)
    }
}
