import SwiftUI

extension AppMarkdownCodeBlockPalette {
    static func fillColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: fillNSColor(isDark: colorScheme == .dark))
    }

    static func borderColor(for colorScheme: ColorScheme) -> Color {
        Color(nsColor: borderNSColor(isDark: colorScheme == .dark))
    }
}
