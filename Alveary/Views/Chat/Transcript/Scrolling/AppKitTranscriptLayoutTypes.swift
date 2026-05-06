import AppKit

// AppKit owns transcript scrolling because SwiftUI lazy-list recycling and
// measurement were not adequate for Alveary's variable-height rows at the time
// of writing; explicit frames let us preserve anchors through growth and prepends.
@MainActor
struct AppKitTranscriptLayoutRow {
    let id: String
    let view: NSView
}

@MainActor
struct AppKitTranscriptVisibleAnchor: Equatable {
    let rowID: String
    let offsetWithinRow: CGFloat
    let generation: Int
}

extension CGRect {
    func isApproximatelyEqual(to other: CGRect) -> Bool {
        abs(minX - other.minX) <= 0.5 &&
            abs(minY - other.minY) <= 0.5 &&
            abs(width - other.width) <= 0.5 &&
            abs(height - other.height) <= 0.5
    }
}
