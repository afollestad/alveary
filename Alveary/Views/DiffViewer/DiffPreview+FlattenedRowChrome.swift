import SwiftUI

extension View {
    func diffPreviewFlattenedHunkRow(isLastInHunk: Bool, bottomPadding: CGFloat) -> some View {
        diffPreviewMinimumContentWidthFrame()
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: isLastInHunk ? 12 : 0,
                        bottomTrailing: isLastInHunk ? 12 : 0,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
            )
            .padding(.bottom, bottomPadding)
    }
}
