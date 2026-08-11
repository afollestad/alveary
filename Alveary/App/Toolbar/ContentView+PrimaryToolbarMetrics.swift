import SwiftUI

/// Everything the primary toolbar button group measures itself with: sizing
/// tokens, the per-boundary optical spacing, glyph ink measurement, and the
/// group's reserved width. Split out of
/// `ContentView+PrimaryToolbarButtonGroup.swift` to keep that file under the
/// length limit.
enum PrimaryToolbarMetrics {
    /// The nominal gap between two same-width glyphs. The toolbar row itself
    /// spaces optically through `PrimaryToolbarOpticalSpacing`; this is the
    /// baseline those values are derived from, and it still spaces the main-pane
    /// header, whose controls are uniform.
    static let buttonSpacing: CGFloat = 4
    static let containerHorizontalInset: CGFloat = 8
    static let containerVerticalInset: CGFloat = 4
    static let containerBorderWidth: CGFloat = 1
    static let iconButtonSize: CGFloat = 30
    static let iconFont = Font.system(size: 16, weight: .medium)
    /// Octicons are fixed-canvas artwork rather than font-sized symbols, so they
    /// need an explicit glyph box that optically matches `iconFont` in this row.
    /// The 16px artwork under-fills its canvas next to a 16pt SF Symbol — at a
    /// 16pt box the diff and pull-request glyphs measure 14.0 and 13.5 points of
    /// ink against `terminal`'s 18.5 — so it renders at an 18pt box here.
    static let octiconSize: CGFloat = 18
    static let statusFont = Font.body.weight(.medium)
    static let statusSpacing: CGFloat = 2
    static let diffSummarySpacing: CGFloat = 6
    static let diffSummaryTrailingPadding: CGFloat = 4
    static let progressIndicatorSize: CGFloat = 16
    static let badgeDiameter: CGFloat = 8
    static let statusAnimation = Animation.spring(response: 0.24, dampingFraction: 0.9)
    static let interactionAnimation = Animation.easeOut(duration: 0.12)
}

/// A toolbar gap is read glyph edge to glyph edge, not box to box: with every
/// box at `iconButtonSize` the visible gap is `iconButtonSize + spacing -
/// (inkA + inkB) / 2`. Ink varies widely between these glyphs even at a shared
/// box size — measured off the recorded baselines, `terminal` draws 18.5pt and
/// `gearshape` 17.0 against 16.0 for the diff octicon and 15.0 for the
/// pull-request one — so a uniform `buttonSpacing` pushes the narrow ones visibly
/// further apart. The two adjacent octicons sat 20.5pt apart against 15.0pt for a
/// dense SF-to-SF pair before this.
///
/// Each value is `buttonSpacing` minus how far that boundary's mean ink falls
/// short of a dense SF-to-SF pair's, so every gap in the row reads alike. These
/// cover the boundaries whose glyphs are fixed at compile time; the project-action
/// strip's symbols are chosen per project, so it derives its spacing at runtime
/// through `PrimaryToolbarGlyphInk` instead. Swapping one of these glyphs means
/// re-deriving the matching value — see the measurement note in
/// `Alveary/App/Toolbar/AGENTS.md`.
enum PrimaryToolbarOpticalSpacing {
    /// Terminal (SF Symbol) → diff viewer (octicon). Both rectangular and dense,
    /// so ink and perceived edge agree here.
    static let beforeDiffViewer: CGFloat = 2.5
    /// Diff viewer (octicon) → pull request (octicon). The narrowest pair in the
    /// row, so this is the tightest value; the boxes still clear each other.
    static let beforePullRequest: CGFloat = 0.5
    /// Pull request, or the diff viewer when no pull request is shown, → settings
    /// (SF Symbol). One value covers both: the two glyphs' ink differs by half a
    /// point, so their exact spacings would differ by half that — finer than the
    /// baselines resolve, and both boundaries measure the same gap.
    ///
    /// Do not tighten this from a screen-measuring tool's reading. The pull-request
    /// glyph ends in a small isolated circle that edge detection drops, which
    /// inflates the reported gap by about 2.5pt; measured ink to ink, this
    /// boundary already matches the rest of the row.
    static let beforeSettings: CGFloat = 1.5
}

/// How wide a toolbar glyph's mark actually draws, in points — the extent that
/// reads as ink, not the box it sits in.
///
/// This exists for the project-action strip, the one part of the row whose glyphs
/// are not known until a project is loaded. SF Symbols vary by about 4 points of
/// ink at this size, which is 2 points of gap either way, so a fixed spacing there
/// is visibly wrong for half the symbols a user might pick.
///
/// Measurement goes through SwiftUI's own renderer because that is the only source
/// that agrees with what ships. `NSImage(systemSymbolName:)` reports `safari` at
/// 18.0 against the 16.0 SwiftUI draws — it counts the outermost antialiased arc
/// of a thin round stroke, and no alpha threshold removes the difference. That 2pt
/// error is the entire size of the defect this corrects.
@MainActor
enum PrimaryToolbarGlyphInk {
    /// Spacing that leaves `opticalGap` of visible space between two glyphs whose
    /// boxes are both `iconButtonSize`. Clamped at zero: two hover selectors must
    /// never overlap, so an unusually wide pair simply sits box edge to box edge.
    static func spacing(after leadingSymbol: String, before trailingSymbol: String) -> CGFloat {
        spacing(after: width(ofSymbol: leadingSymbol), before: width(ofSymbol: trailingSymbol))
    }

    static func spacing(after leadingInk: CGFloat, before trailingInk: CGFloat) -> CGFloat {
        max(opticalGap - PrimaryToolbarMetrics.iconButtonSize + (leadingInk + trailingInk) / 2, 0)
    }

    /// `terminal` is the glyph the action strip always butts against.
    static var terminalInk: CGFloat {
        width(ofSymbol: "terminal")
    }

    static func width(ofSymbol name: String) -> CGFloat {
        if let cached = cache[name] {
            return cached
        }

        let measured = measuredWidth(ofSymbol: name) ?? fallbackWidth
        cache[name] = measured
        return measured
    }

    /// The gap every boundary in the row aims for, glyph edge to glyph edge. It is
    /// what a dense SF-to-SF pair produces at `buttonSpacing`, which is the rhythm
    /// the fixed boundaries were tuned to.
    private static let opticalGap: CGFloat = 15.25
    /// Used when a symbol will not render — a name from a project config that this
    /// OS does not publish. Close to the median SF Symbol width at this size, so an
    /// unknown symbol spaces like a typical one rather than collapsing.
    private static let fallbackWidth: CGFloat = 18
    /// Rendering is the expensive part, so each symbol is measured once. A project's
    /// action symbols are few and fixed for the life of the row.
    private static var cache: [String: CGFloat] = [:]
    private static let renderScale: CGFloat = 4
    /// Matches the threshold the recorded baselines are measured with, so runtime
    /// values and baseline values are the same quantity.
    private static let inkLuminanceCutoff = 175

    private static func measuredWidth(ofSymbol name: String) -> CGFloat? {
        let renderer = ImageRenderer(
            content: Image(systemName: name)
                .font(PrimaryToolbarMetrics.iconFont)
                .foregroundStyle(.black)
                .frame(
                    width: PrimaryToolbarMetrics.iconButtonSize,
                    height: PrimaryToolbarMetrics.iconButtonSize
                )
        )
        renderer.scale = renderScale

        guard let image = renderer.cgImage else {
            return nil
        }
        return inkWidth(of: image)
    }

    private static func inkWidth(of image: CGImage) -> CGFloat? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        // The context must be created, drawn into, and read inside this closure:
        // a `CGContext` keeps the buffer pointer past the call that made it, and an
        // `&pixels` conversion is only valid for the duration of that one call.
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drew else {
            return nil
        }

        var minColumn = width
        var maxColumn = -1
        for column in 0..<width
        where columnHasInk(pixels, column: column, height: height, width: width) {
            minColumn = min(minColumn, column)
            maxColumn = max(maxColumn, column)
        }

        guard maxColumn >= minColumn else {
            return nil
        }
        return CGFloat(maxColumn - minColumn + 1) / renderScale
    }

    private static func columnHasInk(_ pixels: [UInt8], column: Int, height: Int, width: Int) -> Bool {
        for row in 0..<height {
            let offset = (row * width + column) * 4
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0 else {
                continue
            }
            // Composite onto white and threshold on perceived darkness, matching how
            // the recorded baselines are scanned; a faint antialiased edge is ink to
            // a bounding box but not to the eye.
            let luminance = (Int(pixels[offset]) * 299
                + Int(pixels[offset + 1]) * 587
                + Int(pixels[offset + 2]) * 114) / 1000
            if 255 - (255 - luminance) * alpha / 255 < inkLuminanceCutoff {
                return true
            }
        }
        return false
    }
}

@MainActor
enum PrimaryToolbarGroupWidth {
    /// Takes the symbols rather than a count because each boundary's spacing is
    /// derived from the ink of the two glyphs it separates — see
    /// `PrimaryToolbarGlyphInk`.
    static func projectActionStripWidth(symbols: [String]) -> CGFloat {
        guard let first = symbols.first else {
            return 0
        }

        var width = CGFloat(symbols.count) * PrimaryToolbarMetrics.iconButtonSize
        var previous = first
        for symbol in symbols.dropFirst() {
            width += PrimaryToolbarGlyphInk.spacing(after: previous, before: symbol)
            previous = symbol
        }
        return width
    }

    static func projectActionsSlotWidth(symbols: [String]) -> CGFloat {
        guard let last = symbols.last else {
            return 0
        }

        return projectActionStripWidth(symbols: symbols)
            + PrimaryToolbarGlyphInk.spacing(
                after: PrimaryToolbarGlyphInk.width(ofSymbol: last),
                before: PrimaryToolbarGlyphInk.terminalInk
            )
    }

    /// The pull-request button is conditional, so it rides an animated slot like
    /// the project actions rather than the fixed core-button count. The slot owns
    /// the spacing its presence adds, so collapsing it removes both.
    static func pullRequestSlotWidth(isVisible: Bool) -> CGFloat {
        guard isVisible else {
            return 0
        }
        return PrimaryToolbarMetrics.iconButtonSize + PrimaryToolbarOpticalSpacing.beforePullRequest
    }

    static func groupWidth(
        projectActionsSlotWidth: CGFloat,
        pullRequestSlotWidth: CGFloat,
        diffStatusWidth: CGFloat
    ) -> CGFloat {
        PrimaryToolbarMetrics.containerHorizontalInset * 2
            + coreToolbarButtonWidth
            + coreToolbarSpacingWidth
            + projectActionsSlotWidth
            + pullRequestSlotWidth
            + diffStatusWidth
    }

    /// Terminal, diff viewer, and settings — the buttons that are always mounted.
    private static let coreToolbarButtonCount: CGFloat = 3
    private static let coreToolbarButtonWidth = coreToolbarButtonCount * PrimaryToolbarMetrics.iconButtonSize
    /// The always-present boundaries: terminal → diff viewer, and whatever
    /// precedes settings. The pull-request slot carries its own.
    private static let coreToolbarSpacingWidth = PrimaryToolbarOpticalSpacing.beforeDiffViewer
        + PrimaryToolbarOpticalSpacing.beforeSettings
}
