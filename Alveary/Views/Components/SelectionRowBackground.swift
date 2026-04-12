import SwiftUI

enum AppSelectionStyle {
    static var rowFill: Color {
        Color.accentColor.opacity(0.26)
    }
}

struct AppSelectionRowBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? AppSelectionStyle.rowFill : Color.clear)
            .padding(.horizontal, 10)
    }
}

extension View {
    func appSelectionRowBackground(isSelected: Bool) -> some View {
        listRowBackground(AppSelectionRowBackground(isSelected: isSelected))
    }
}
