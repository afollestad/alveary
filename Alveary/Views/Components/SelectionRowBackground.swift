import SwiftUI

enum AppSelectionStyle {
    static var rowFill: Color {
        Color.accentColor.opacity(0.26)
    }
}

struct AppSelectionRowBackground: View {
    let isSelected: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(isSelected ? AppSelectionStyle.rowFill : Color.clear)
            .padding(.horizontal, 10)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
    }
}

extension View {
    func appSelectionRowBackground(
        isSelected: Bool,
        topInset: CGFloat = 0,
        bottomInset: CGFloat = 0
    ) -> some View {
        listRowBackground(
            AppSelectionRowBackground(
                isSelected: isSelected,
                topInset: topInset,
                bottomInset: bottomInset
            )
        )
    }
}
