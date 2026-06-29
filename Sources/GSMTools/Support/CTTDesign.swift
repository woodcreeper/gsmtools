import SwiftUI

enum CTTColor {
    static func canvas(_ scheme: ColorScheme) -> Color { color(light: "#F7F8F9", dark: "#14181C", scheme) }
    static func panel(_ scheme: ColorScheme) -> Color { color(light: "#EEF1F3", dark: "#1D232A", scheme) }
    static func paper(_ scheme: ColorScheme) -> Color { color(light: "#FFFFFF", dark: "#222931", scheme) }
    static func titlebar(_ scheme: ColorScheme) -> Color { color(light: "#F1F4F6", dark: "#1A2026", scheme) }
    static func sidebar(_ scheme: ColorScheme) -> Color { color(light: "#EAF5FB", dark: "#0B3349", scheme) }
    static func navOn(_ scheme: ColorScheme) -> Color { color(light: "#CFE6F2", dark: "#14506B", scheme) }
    static func rowSelected(_ scheme: ColorScheme) -> Color { color(light: "#EAF5FB", dark: "#1C2A33", scheme) }
    static func track(_ scheme: ColorScheme) -> Color { color(light: "#E3E7EA", dark: "#2A323A", scheme) }
    static func ink(_ scheme: ColorScheme) -> Color { color(light: "#0A0C0E", dark: "#FFFFFF", scheme) }
    static func line(_ scheme: ColorScheme) -> Color { color(light: "#DCE1E5", dark: "#39424B", scheme) }
    static func line2(_ scheme: ColorScheme) -> Color { color(light: "#EAEDF0", dark: "#2A323A", scheme) }
    static func fg2(_ scheme: ColorScheme) -> Color { color(light: "#2A3138", dark: "#BEC6CC", scheme) }
    static func fg3(_ scheme: ColorScheme) -> Color { color(light: "#5E6770", dark: "#8B959D", scheme) }
    static func green(_ scheme: ColorScheme) -> Color { color(light: "#2F8F4E", dark: "#43A864", scheme) }
    static func ghost(_ scheme: ColorScheme) -> Color { color(light: "#BEC6CC", dark: "#5E6770", scheme) }
    static func ochre(_ scheme: ColorScheme) -> Color { color(light: "#D98A1B", dark: "#E2A23A", scheme) }
    static func vermilion(_ scheme: ColorScheme) -> Color { color(light: "#C24A2E", dark: "#D4583B", scheme) }
    static func fallback(_ scheme: ColorScheme) -> Color { color(light: "#4295BD", dark: "#4CAFE8", scheme) }
    static func accent(_ scheme: ColorScheme) -> Color { color(light: "#4295BD", dark: "#4CAFE8", scheme) }
    static func accentSoft(_ scheme: ColorScheme) -> Color { color(light: "#EAF5FB", dark: "#13303F", scheme) }
    static func map1(_ scheme: ColorScheme) -> Color { color(light: "#E8EDF1", dark: "#1E262D", scheme) }
    static func map2(_ scheme: ColorScheme) -> Color { color(light: "#E2E8ED", dark: "#222B33", scheme) }

    private static func color(light: String, dark: String, _ scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? dark : light)
    }
}

enum CTTFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(weight == .heavy ? "BarlowCondensed-ExtraBold" : "BarlowCondensed-Bold", size: size)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black:
            name = "Barlow-Bold"
        case .semibold, .medium:
            name = "Barlow-SemiBold"
        default:
            name = "Barlow-Regular"
        }
        return .custom(name, size: size)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Regular", size: size)
    }

    static func label(_ size: CGFloat = 10) -> Font {
        ui(size, weight: .semibold)
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

struct CTTCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(CTTColor.paper(scheme))
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(CTTColor.line2(scheme), lineWidth: 1)
            }
    }
}

extension View {
    func cttCard(radius: CGFloat = 8) -> some View {
        modifier(CTTCard(radius: radius))
    }
}
