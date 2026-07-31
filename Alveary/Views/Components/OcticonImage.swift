import SwiftUI

/// Primer Octicons ship as fixed-canvas artwork (16px or 24px variants), so
/// unlike SF Symbols they do not size by font — every call site states its own
/// glyph box. Tint comes from the ambient `foregroundStyle`, so a button
/// style's enabled/hover treatment applies. Prefer the 16px variant when the
/// glyph sits beside SF Symbols: its strokes are drawn bolder for small sizes,
/// while the 24px artwork renders visibly thinner at the same frame.
struct OcticonImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
