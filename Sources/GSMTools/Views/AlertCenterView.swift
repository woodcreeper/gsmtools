import GSMToolsCore
import SwiftUI

struct AlertCenterView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @State private var filter: AlertFilter = .all

    private var filteredAlerts: [AlertFlag] {
        model.alerts.filter { filter.includes($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HeaderView(
                    title: "Alerts",
                    subtitle: "Alerts are generated from completed runs and link back to the data window that produced the flag.",
                    infoBullets: [
                        "Filter chips change the visible list; they do not change the saved alerts.",
                        "Open Devices jumps back to the run evidence for the flagged transmitter.",
                        "Behavior rules are planned for classified patterns such as nesting."
                    ],
                    infoLegendItems: [
                        InfoPopoverLegendItem(
                            title: "All",
                            detail: "Every generated alert for completed runs.",
                            systemImage: "tray.full",
                            color: .ink
                        ),
                        InfoPopoverLegendItem(
                            title: "Deviation",
                            detail: "Telemetry changes or absolute health flags: GPS, check-ins, fix time, solar, battery, temperature, or activity.",
                            systemImage: "waveform.path.ecg",
                            color: .vermilion
                        ),
                        InfoPopoverLegendItem(
                            title: "Behavior",
                            detail: "Classified biological or operational patterns, such as likely nesting, once behavior rules are enabled.",
                            systemImage: "bell.badge",
                            color: .fallback
                        ),
                        InfoPopoverLegendItem(
                            title: "Baseline",
                            detail: "The app did not have enough reference history for a stronger comparison.",
                            systemImage: "clock.badge.exclamationmark",
                            color: .ochre
                        )
                    ]
                )

                HStack(spacing: 8) {
                    ForEach(AlertFilter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            Text(option.title(model.alerts))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(filter == option ? .white : CTTColor.fg2(scheme))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(filter == option ? CTTColor.ink(scheme) : CTTColor.paper(scheme))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(CTTColor.line2(scheme), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if filteredAlerts.isEmpty {
                    ContentUnavailableView("No matching alerts", systemImage: "bell", description: Text("Run an analysis to create deviation and behavior flags."))
                        .frame(minHeight: 220)
                        .cttCard()
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredAlerts) { flag in
                            AlertCard(flag: flag, run: run(for: flag))
                        }
                    }
                }

                BehaviorRulePrompt()
            }
            .padding(18)
        }
        .background(CTTColor.canvas(scheme))
    }

    private func run(for flag: AlertFlag) -> AnalysisRun? {
        guard let runId = flag.runId else { return nil }
        return model.runs.first { $0.id == runId }
    }
}

private enum AlertFilter: String, CaseIterable, Identifiable {
    case all
    case deviation
    case behavior
    case baseline

    var id: String { rawValue }

    func title(_ alerts: [AlertFlag]) -> String {
        "\(label) · \(alerts.filter(includes).count)"
    }

    private var label: String {
        switch self {
        case .all: return "All"
        case .deviation: return "Deviation"
        case .behavior: return "Behavior"
        case .baseline: return "Baseline"
        }
    }

    func includes(_ flag: AlertFlag) -> Bool {
        switch self {
        case .all:
            return true
        case .deviation:
            return flag.metric != .nestingLikelihood && flag.mode != .insufficientBaseline
        case .behavior:
            return flag.metric == .nestingLikelihood
        case .baseline:
            return flag.mode == .insufficientBaseline
        }
    }
}

private struct AlertCard: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    let flag: AlertFlag
    let run: AnalysisRun?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(CTTColor.ink(scheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(flag.severity.rawValue)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(color)
                }

                Text(flag.message)
                    .font(.system(size: 13))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                Text(dataUsed)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CTTColor.fg3(scheme))
                    .lineLimit(2)

                HStack {
                    Text(flag.mode.displayName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    Button {
                        if let run {
                            model.openResults(for: run, focusIMEI: flag.imei)
                        }
                    } label: {
                        Label("Open Devices", systemImage: "waveform.path.ecg")
                    }
                    .controlSize(.small)
                    .disabled(run == nil)
                }
            }
        }
        .padding(12)
        .background(CTTColor.paper(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(CTTColor.line2(scheme), lineWidth: 1)
        }
    }

    private var title: String {
        let unit = flag.imei.map(shortIMEI) ?? "fleet"
        return "\(unit) · \(flag.metric.rawValue)"
    }

    private var dataUsed: String {
        guard let run else {
            return "Data used: saved alert · \(Formatters.shortDateTime.string(from: flag.createdAt))"
        }
        return "Run: \(run.name) · \(run.analysisMode?.displayName ?? "selected period") · \(Formatters.shortDateTime.string(from: run.startDate)) → \(Formatters.shortDateTime.string(from: run.endDate))"
    }

    private var color: Color {
        switch flag.severity {
        case .critical: return CTTColor.vermilion(scheme)
        case .warning: return CTTColor.ochre(scheme)
        case .info: return CTTColor.fallback(scheme)
        }
    }

    private func shortIMEI(_ imei: String) -> String {
        guard imei.count > 8 else { return imei }
        return "…\(imei.suffix(4))"
    }
}

private struct BehaviorRulePrompt: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bell.badge")
                .foregroundStyle(CTTColor.fallback(scheme))
            Text("Behavior rules")
                .font(CTTFont.ui(13, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))
            Spacer()
            Button {
            } label: {
                Label("New rule", systemImage: "plus")
            }
            .controlSize(.small)
            .disabled(true)
            .help("Behavior rule builder is planned after the telemetry run flow.")
        }
        .padding(13)
        .background(CTTColor.accentSoft(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private extension FlagMode {
    var displayName: String {
        switch self {
        case .statistical:
            return "statistical"
        case .threshold:
            return "threshold"
        case .insufficientBaseline:
            return "baseline needed"
        }
    }
}
