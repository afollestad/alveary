import SwiftUI

/// A button glyph sourced from either SF Symbols or the vendored Primer
/// Octicons. One vocabulary covers both the SwiftUI action buttons and the
/// AppKit transcript buttons, so a concept keeps the same glyph wherever it
/// appears — a pull-request action is the pull-request octicon in the Diff
/// Viewer footer and in a transcript card alike.
enum ActionIcon: Equatable {
    case system(String)
    case octicon(Octicon)
}

/// Renders an `ActionIcon`. SF Symbols size by font and inherit whatever the
/// surrounding style applies; octicons are fixed-canvas artwork that ignores
/// `imageScale`, so they need an explicit glyph box. `octiconSize` defaults to
/// the box calibrated for the shared prominent button styles — pass a different
/// one only for a different type size, never to nudge a single call site.
struct ActionIconImage: View {
    let icon: ActionIcon
    var octiconSize: CGFloat = ActionButtonMetrics.octiconGlyphSize

    var body: some View {
        switch icon {
        case .system(let name):
            Image(systemName: name)
        case .octicon(let octicon):
            OcticonImage(octicon: octicon, size: octiconSize)
        }
    }
}

/// The two type sizes icon+text buttons come in. Bundling the glyph box with
/// the gap beside it keeps a caller from pairing a caption-sized glyph with the
/// prominent spacing.
enum ActionButtonLabelScale {
    /// `.body`-sized prominent button styles.
    case prominent
    /// `.plain` affordances at `.font(.caption)`, such as comment-thread actions.
    case inline

    var octiconSize: CGFloat {
        switch self {
        case .prominent:
            return ActionButtonMetrics.octiconGlyphSize
        case .inline:
            return ActionButtonMetrics.inlineOcticonGlyphSize
        }
    }

    var iconLabelSpacing: CGFloat {
        switch self {
        case .prominent:
            return ActionButtonMetrics.iconLabelSpacing
        case .inline:
            return ActionButtonMetrics.inlineIconLabelSpacing
        }
    }
}

/// Icon-plus-text content for action buttons. Deliberately an `HStack` of
/// `Image` and `Text` rather than a `Label`: on macOS the shared prominent
/// styles can render a `Label` as text-only.
struct ActionButtonLabel: View {
    let title: String
    let icon: ActionIcon
    var scale = ActionButtonLabelScale.prominent
    /// Swaps the glyph for a spinner in the glyph's own box, so a button that starts working
    /// cannot change width mid-action.
    var isBusy = false
    /// The label's own color. The `.secondary` working gray the status dots use would vanish
    /// inside a filled pill, which is the only place this spinner appears.
    var busyTint = Color.primary

    var body: some View {
        HStack(spacing: scale.iconLabelSpacing) {
            if isBusy {
                StatusIndicatorSpinner(color: busyTint, diameter: scale.octiconSize)
            } else {
                ActionIconImage(icon: icon, octiconSize: scale.octiconSize)
            }
            Text(title)
        }
    }
}
