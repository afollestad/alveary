import BlockInputKit
import Foundation

/// Table geometry shared by `AppKitMarkdownTableView` and `AppKitMarkdownLayoutMeasurer`. The two must agree
/// exactly — a measured table that disagrees with the drawn one leaves a transcript row reserving
/// space no pixel occupies — so neither side keeps its own copy of these numbers.
enum AppKitMarkdownTableMetrics {
    static let minimumColumnWidth: CGFloat = 120
    static let fallbackViewportWidth: CGFloat = 520
    static let cellHorizontalPadding: CGFloat = 10
    static let cellVerticalPadding: CGFloat = 7

    /// The box a cell's lone image occupies with no column to answer to — the cap that decides how
    /// wide the column has to be. Resolved through the store rather than a decoded bitmap so the
    /// cell reserves the right height before the load lands.
    @MainActor
    static func imageDisplaySize(
        for cellImage: AppMarkdownCellImage,
        store: AppMarkdownImageStore
    ) -> CGSize {
        appMarkdownImageDisplaySize(
            for: resolvedImage(for: cellImage, store: store),
            constrainedTo: appMarkdownTableImageCellMaxSize
        )
    }

    /// The same box inside a column that may be narrower than the cap. Both the renderer's cell and
    /// the measurer size from here; a private copy in either is a parity break waiting to happen.
    ///
    /// Width is the only constraint passed down, because the cap's *width* already carries the
    /// height limit — `imageDisplaySize(for:store:)` scaled both together.
    @MainActor
    static func imageDisplaySize(
        for cellImage: AppMarkdownCellImage,
        store: AppMarkdownImageStore,
        inCellWidth cellWidth: CGFloat
    ) -> CGSize {
        let cappedWidth = imageDisplaySize(for: cellImage, store: store).width
        let interior = max(cellWidth - cellHorizontalPadding * 2, 0)
        return appMarkdownImageDisplaySize(
            for: resolvedImage(for: cellImage, store: store),
            constrainedTo: interior > 0 ? min(cappedWidth, interior) : cappedWidth
        )
    }

    @MainActor
    private static func resolvedImage(
        for cellImage: AppMarkdownCellImage,
        store: AppMarkdownImageStore
    ) -> BlockInputImage {
        cellImage.image.appMarkdownResolved(
            naturalSize: store.naturalSize(for: cellImage.image, baseURL: nil)
        )
    }
}
