import CoreText
import Foundation

enum FontRegistrar {
    private static let fontFiles = [
        "Barlow-Regular.ttf",
        "Barlow-SemiBold.ttf",
        "Barlow-Bold.ttf",
        "BarlowCondensed-Bold.ttf",
        "BarlowCondensed-ExtraBold.ttf",
        "JetBrainsMono-Regular.ttf",
        "JetBrainsMono-Bold.ttf"
    ]

    static func registerBundledFonts() {
        for file in fontFiles {
            let parts = file.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let url = Bundle.module.url(forResource: parts[0], withExtension: parts[1], subdirectory: "Fonts")
            else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
