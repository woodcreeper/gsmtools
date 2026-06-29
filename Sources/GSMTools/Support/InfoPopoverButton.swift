import SwiftUI

struct InfoPopoverButton: View {
    @Environment(\.colorScheme) private var scheme
    @State private var isPresented = false

    let title: String
    let message: String
    var bullets: [String] = []
    var legendItems: [InfoPopoverLegendItem] = []
    var width: CGFloat = 330

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CTTColor.fg3(scheme))
                .frame(width: 18, height: 18)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(CTTFont.ui(14, weight: .bold))
                    .foregroundStyle(CTTColor.ink(scheme))

                Text(message)
                    .font(CTTFont.ui(12, weight: .medium))
                    .foregroundStyle(CTTColor.fg2(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                if !bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(CTTColor.accent(scheme))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 6)
                                Text(bullet)
                                    .font(CTTFont.ui(12, weight: .medium))
                                    .foregroundStyle(CTTColor.fg2(scheme))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                if !legendItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(legendItems) { item in
                            HStack(alignment: .top, spacing: 9) {
                                LegendMark(item: item)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(CTTFont.ui(12, weight: .bold))
                                        .foregroundStyle(CTTColor.ink(scheme))
                                    Text(item.detail)
                                        .font(CTTFont.ui(11, weight: .medium))
                                        .foregroundStyle(CTTColor.fg2(scheme))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(width: width, alignment: .leading)
            .background(.regularMaterial)
        }
        .accessibilityLabel("About \(title)")
    }
}

struct InfoPopoverLegendItem: Identifiable {
    var id: String { "\(title)-\(detail)" }
    let title: String
    let detail: String
    let systemImage: String?
    let color: InfoPopoverLegendColor

    init(title: String, detail: String, systemImage: String? = nil, color: InfoPopoverLegendColor = .accent) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.color = color
    }
}

enum InfoPopoverLegendColor {
    case accent
    case green
    case ochre
    case vermilion
    case fallback
    case ghost
    case ink

    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .accent: return CTTColor.accent(scheme)
        case .green: return CTTColor.green(scheme)
        case .ochre: return CTTColor.ochre(scheme)
        case .vermilion: return CTTColor.vermilion(scheme)
        case .fallback: return CTTColor.fallback(scheme)
        case .ghost: return CTTColor.ghost(scheme)
        case .ink: return CTTColor.ink(scheme)
        }
    }
}

private struct LegendMark: View {
    @Environment(\.colorScheme) private var scheme
    let item: InfoPopoverLegendItem

    var body: some View {
        Group {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .frame(width: 13, height: 13)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 22, height: 22)
        .background(item.color.color(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
