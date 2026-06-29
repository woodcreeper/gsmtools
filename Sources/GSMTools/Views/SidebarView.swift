import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var model: AppModel
    @Binding var selection: AppSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(AppSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    SidebarRow(
                        section: section,
                        isSelected: selection == section,
                        badge: section == .alerts && !model.alerts.isEmpty ? "\(model.alerts.count)" : nil
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text("API throttle")
                        .font(CTTFont.label(9))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(CTTColor.fg3(scheme))
                    InfoPopoverButton(
                        title: "API throttle",
                        message: "Telemetry pulls are paced to the API limit so large runs do not exceed the service rate. Active means the app is currently fetching or refreshing data.",
                        width: 300
                    )
                }
                Text(model.isLoading ? "● 60/min · active" : "● 60/min · idle")
                    .font(CTTFont.mono(10))
                    .foregroundStyle(CTTColor.green(scheme))
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(CTTColor.line(scheme))
                    .frame(height: 1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 12)
        .frame(minWidth: 150, idealWidth: 150, maxWidth: 170)
        .background(CTTColor.sidebar(scheme))
    }
}

private struct SidebarRow: View {
    @Environment(\.colorScheme) private var scheme
    let section: AppSection
    let isSelected: Bool
    let badge: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 16)
                .foregroundStyle(isSelected ? CTTColor.ink(scheme) : CTTColor.fg2(scheme).opacity(0.75))

            Text(section.title)
                .font(CTTFont.ui(12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? CTTColor.ink(scheme) : CTTColor.fg2(scheme))

            Spacer(minLength: 4)

            if let badge {
                Text(badge)
                    .font(CTTFont.mono(9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(CTTColor.vermilion(scheme))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? CTTColor.navOn(scheme) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
