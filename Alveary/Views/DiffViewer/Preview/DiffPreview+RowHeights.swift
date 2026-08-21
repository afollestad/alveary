import SwiftUI

/// Heights the rendered rows have reported, keyed by ``FlattenedDiffPreviewRow/heightKey(collapsedFileIDs:)``.
///
/// A reference type for the same reason ``DiffPreviewScrollOffset`` is one: a measurement write must
/// invalidate only the modifier that declares the stream's height, never the body holding the row
/// stream itself. Rows that draw identically share a key, so one measurement sizes every one of
/// them and the whole stream settles within the first screenful.
@Observable
final class DiffPreviewRowHeights {
    private(set) var measured: [String: CGFloat] = [:]

    /// Ignores sub-point noise, because the write feeds the content height that this row is laid
    /// out inside — a jitter loop there would re-run the layout every frame. A zero is a row that
    /// has not been laid out yet rather than one that draws nothing, so it never displaces a real
    /// measurement.
    func record(_ height: CGFloat, for key: String) {
        guard height > 0 else {
            return
        }
        if let existing = measured[key], abs(existing - height) < 0.5 {
            return
        }
        measured[key] = height
    }
}

/// How tall the row stream will draw, so the scroll view can be told a height rather than deriving
/// one from `LazyVStack`'s estimate.
///
/// The estimate is what this exists to replace: it sizes rows it has not built from the mean of the
/// realized window, so a single 127pt comment card among ~21pt line rows inflated every unrealized
/// row and left thousands of points of dead scroll space below the last row of a commented pull
/// request diff. Counting rows by key instead makes the total exact for every kind already on
/// screen, and wrong only by the difference between a fallback and the truth for comment cards that
/// have never been drawn — an error in the number of comments, not the number of comments times the
/// number of rows.
struct FlattenedDiffPreviewHeightPlan: Sendable {
    struct Entry: Sendable {
        var count: Int
        /// Stands in until a row with this key has reported its real height.
        var fallback: CGFloat
        /// Comment rows, whose height is their content's rather than their kind's. One of these
        /// still unmeasured borrows the average of its measured siblings, which is far closer than
        /// the static fallback — cards on one pull request are alike.
        var isVariable: Bool
    }

    private(set) var entries: [String: Entry] = [:]

    mutating func add(_ row: FlattenedDiffPreviewRow, collapsedFileIDs: Set<String>) {
        let key = row.heightKey(collapsedFileIDs: collapsedFileIDs)
        entries[
            key,
            default: Entry(count: 0, fallback: row.fallbackHeight, isVariable: row.hasContentDrivenHeight)
        ].count += 1
    }

    /// Under-reserving cannot strand a row: the shortfall always sits *below* the unmeasured row
    /// that caused it, so scrolling far enough to need the missing range is what realizes that row
    /// and corrects the total.
    func total(using heights: DiffPreviewRowHeights) -> CGFloat {
        let measuredVariable = entries.compactMap { key, entry in
            entry.isVariable ? heights.measured[key] : nil
        }
        let variableFallback = measuredVariable.isEmpty
            ? nil
            : measuredVariable.reduce(0, +) / CGFloat(measuredVariable.count)

        return entries.reduce(0) { running, entry in
            let fallback = entry.value.isVariable
                ? (variableFallback ?? entry.value.fallback)
                : entry.value.fallback
            return running + CGFloat(entry.value.count) * (heights.measured[entry.key] ?? fallback)
        }
    }
}

extension FlattenedDiffPreviewRow {
    // swiftlint:disable cyclomatic_complexity
    /// Groups rows that draw to the same height. Everything that varies the drawn height belongs in
    /// the key — the paddings the row model hands out, and a file header's collapse state, which
    /// changes its bottom padding. Comment rows key by id instead: each card's height is its own.
    ///
    /// Exhaustive rather than split around a `default`, so a new row kind cannot compile until it
    /// has said how it keys; sharing another kind's key would silently mis-size it.
    func heightKey(collapsedFileIDs: Set<String>) -> String {
        switch self {
        case .fileHeader(_, let fileID, _, let topPadding):
            return "fileHeader:\(topPadding):\(collapsedFileIDs.contains(fileID))"
        case .renameSummary:
            return "renameSummary"
        case .imagePreview:
            return "imagePreview"
        case .binaryCallout:
            return "binaryCallout"
        case .emptyCallout(_, let isRenamed):
            return "emptyCallout:\(isRenamed)"
        case .hunkHeader(_, _, let topPadding):
            return "hunkHeader:\(topPadding)"
        case .line(_, _, _, let isLastInHunk, let bottomPadding, _):
            return "line:\(isLastInHunk):\(bottomPadding)"
        case .collapsed(_, _, _, let isLastInHunk, let bottomPadding):
            return "collapsed:\(isLastInHunk):\(bottomPadding)"
        case .fileContentSpacer(_, let height):
            return "spacer:\(height)"
        case .commentThread(let id, _, _, _, _, _):
            return "commentThread:\(id)"
        case .commentComposer(let id, _, _, _, _):
            return "commentComposer:\(id)"
        }
    }
    // swiftlint:enable cyclomatic_complexity

    /// Whether the row's height comes from its content rather than its kind, so one measurement
    /// cannot size every row sharing the key.
    var hasContentDrivenHeight: Bool {
        switch self {
        case .commentThread, .commentComposer:
            return true
        case .fileHeader, .renameSummary, .imagePreview, .binaryCallout, .emptyCallout,
             .hunkHeader, .line, .collapsed, .fileContentSpacer:
            return false
        }
    }

    /// Only ever used for a key no row has drawn yet, so it is deliberately rough — generous on the
    /// comment rows, since a total that falls short of what is drawn would strand the last rows
    /// outside the scroll range.
    var fallbackHeight: CGFloat {
        switch self {
        case .fileHeader(_, _, _, let topPadding):
            return 44 + topPadding
        case .renameSummary:
            return 34
        case .imagePreview:
            return DiffViewerPaneMetrics.diffPreviewImageRowHeight + 14
        case .binaryCallout, .emptyCallout:
            return 96
        case .hunkHeader(_, _, let topPadding):
            return 25 + topPadding
        case .line(_, _, _, _, let bottomPadding, _),
             .collapsed(_, _, _, _, let bottomPadding):
            return 21 + bottomPadding
        case .fileContentSpacer(_, let height):
            return height
        case .commentThread(_, _, _, _, _, let bottomPadding),
             .commentComposer(_, _, _, _, let bottomPadding):
            return 220 + bottomPadding
        }
    }
}

/// Reports one row's drawn height into the shared cache. Writes only; it reads nothing observable,
/// so a measurement never re-runs the row itself.
struct DiffPreviewRowHeightReporter: ViewModifier {
    let key: String

    @Environment(DiffPreviewRowHeights.self) private var heights: DiffPreviewRowHeights?

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            heights?.record(height, for: key)
        }
    }
}

/// Declares the row stream's height from the plan. The cache is read out of the environment, which
/// is optional by construction, so the flexible frame stays as the no-cache branch — that is the
/// pre-plan behavior, and falling back to it degrades to a stale estimate rather than a broken
/// layout.
struct DiffPreviewContentHeightModifier: ViewModifier {
    let plan: FlattenedDiffPreviewHeightPlan

    @Environment(DiffPreviewRowHeights.self) private var heights: DiffPreviewRowHeights?

    func body(content: Content) -> some View {
        if let heights {
            content.frame(height: plan.total(using: heights), alignment: .topLeading)
        } else {
            content.frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
