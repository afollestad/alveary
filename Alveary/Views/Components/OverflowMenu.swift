import SwiftUI

/// The three-dot overflow menu's glyph and footprint, split out of `AppOverflowMenu`
/// because static stored properties are illegal on a generic type — and because one
/// surface cannot mount the SwiftUI view at all: the transcript's review-proposal card
/// is AppKit and rebuilds the control by hand, reaching these through
/// `PullRequestCommentActionsMenu`'s forwarding statics. A glyph or hit target that
/// drifts on one surface stops reading as the same control, so both take them from here.
enum AppOverflowMenuMetrics {
    static let glyphSymbolName = "ellipsis"
    static let glyphPointSize: CGFloat = 11

    /// The bare glyph is a sliver; this is the control's real hit target, and also the
    /// hover circle `iconActionButtonStyle(.inline)` draws inside it, so the glyph
    /// *centers* rather than trailing-aligning. A surface placing the menu on a pane's
    /// shared trailing column therefore owes it
    /// `contextualPaneTrailingGlyphLane(controlWidth:)` — it no longer lands on the
    /// axis by construction the way a trailing-aligned glyph did.
    static let hitTargetSize = CGSize(
        width: ActionButtonMetrics.inlineIconButtonDiameter,
        height: ActionButtonMetrics.inlineIconButtonDiameter
    )
}

/// The app's three-dot overflow menu, mounted wherever secondary actions hide behind a
/// glyph, so their hover circle and press feedback stay identical across surfaces.
///
/// Empty `content` still renders a live but empty menu, so a caller with nothing to
/// offer must gate mounting rather than passing no rows.
struct AppOverflowMenu<Content: View>: View {
    /// Both the hover tooltip and the VoiceOver name; the glyph carries no text, so
    /// without this the control is unnamed for sighted and assistive users alike.
    let name: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu {
            content
        } label: {
            Image(systemName: AppOverflowMenuMetrics.glyphSymbolName)
                .font(.system(size: AppOverflowMenuMetrics.glyphPointSize, weight: .semibold))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        // The tint rides the style's parameter rather than a local `foregroundStyle`,
        // so the glyph still fades through hover and pressed.
        .iconActionButtonStyle(.inline, foregroundColor: .secondary)
        .fixedSize()
        .help(name)
        .accessibilityLabel(name)
    }
}

/// A row inside an `AppOverflowMenu`. It exists so `.labelStyle(.titleAndIcon)` is
/// spelled once: macOS menu rows default to a title-only style, so a bare
/// `Label(_:systemImage:)` silently renders glyph-less, and every caller repeating the
/// modifier is a caller that can forget it.
struct AppOverflowMenuRow: View {
    let title: String
    let systemImage: String
    /// `.destructive` renders the row red, the app's convention for a row that throws
    /// work away.
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
        }
    }
}
