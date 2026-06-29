import SwiftUI

struct HeaderView: View {
    @Environment(\.colorScheme) private var scheme

    let title: String
    let subtitle: String
    var infoTitle: String?
    var infoBullets: [String] = []
    var infoLegendItems: [InfoPopoverLegendItem] = []

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(CTTFont.display(28, weight: .bold))
                .foregroundStyle(CTTColor.ink(scheme))

            if !subtitle.isEmpty {
                InfoPopoverButton(
                    title: infoTitle ?? title,
                    message: subtitle,
                    bullets: infoBullets,
                    legendItems: infoLegendItems,
                    width: infoLegendItems.isEmpty ? 330 : 420
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
