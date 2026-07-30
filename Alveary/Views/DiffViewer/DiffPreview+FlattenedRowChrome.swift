import SwiftUI

/// The tint bands a comment row paints behind its floating card so the
/// neighboring diff line colors pass through around the card's edges: the top
/// band continues the anchored line above, the bottom band the line below
/// (falling back to the anchored line at a hunk's end). Carries the hunk's
/// gutter layout so the line-number/marker columns and their separator
/// continue through the row at matching color and opacity.
struct DiffCommentRowWash: Sendable {
    let topLineType: DiffLine.LineType
    let bottomLineType: DiffLine.LineType
    let gutterLayout: DiffGutterLayout
}

extension View {
    /// `commentWash` is comment rows' band background over the code surface;
    /// line rows paint their own wash internally and keep the default `nil`.
    func diffPreviewFlattenedHunkRow(
        isLastInHunk: Bool,
        bottomPadding: CGFloat,
        commentWash: DiffCommentRowWash? = nil
    ) -> some View {
        diffPreviewMinimumContentWidthFrame()
            .background {
                if let commentWash {
                    DiffCommentRowWashView(wash: commentWash)
                }
            }
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

/// Two stacked bands splitting the row at half height, each reproducing a
/// line row's layering: the full-width row wash with the darker gutter tint
/// and the 1pt separator over its leading columns.
private struct DiffCommentRowWashView: View {
    let wash: DiffCommentRowWash

    var body: some View {
        VStack(spacing: 0) {
            band(wash.topLineType)
            band(wash.bottomLineType)
        }
    }

    private func band(_ type: DiffLine.LineType) -> some View {
        Rectangle()
            .fill(type.diffLineRowWash)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(type.diffGutterWash)
                        .frame(width: wash.gutterLayout.gutterWidth)

                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 1)
                }
            }
    }
}
