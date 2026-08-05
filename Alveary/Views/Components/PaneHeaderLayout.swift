import SwiftUI

enum PaneHeaderLayout {
    static let height: CGFloat = 64

    /// Horizontal insets shared by pane headers and the scroll content beneath them.
    /// Screen content must reuse these rather than hardcoding its own padding: the
    /// header's actions and the content's rows sit against the same visual edges, so
    /// any divergence reads as a misaligned right or left margin.
    static let leadingInset: CGFloat = 20
    static let trailingInset: CGFloat = 21

    static let verticalPadding: CGFloat = 14

    /// Least room a search field is still worth showing in; below it the header trades
    /// the field for `PaneHeaderSearchButton`.
    static let searchMinimumWidth: CGFloat = 140

    /// Least gap between the leading and trailing regions.
    static let regionSpacing: CGFloat = 12

    /// Air between the search field's solid edge and the actions beside it. Wider than
    /// `actionSpacing` because a filled edge reads closer than a glyph does.
    static let searchFieldSpacing: CGFloat = 10

    /// Default gap inside a header's trailing action cluster. A gap reads glyph edge to
    /// glyph edge rather than box to box, so a header whose icons carry wide marks wants
    /// less — Pull Requests spaces its two at 0 for the same optical width this gives a
    /// narrow `plus`.
    static let actionSpacing: CGFloat = 6
}
