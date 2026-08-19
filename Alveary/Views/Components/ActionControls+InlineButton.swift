import SwiftUI

// The low-emphasis *text* member of the `ActionControls.swift` button family: its opacity ramp,
// its `View` entry point, and the style behind it. Split out only because the shared file was
// over the length limit; the chrome rules it obeys are that file's.

/// Opacity ramp for a low-emphasis *text* affordance whose only hover cue is the label
/// itself brightening: a thread's Reply and Resolve conversation, Show in Changes, and the
/// transcript's Show in PR. Resting sits below full so hover has somewhere to go. The icon
/// family's resting and disabled values carry over unchanged, but hover lands at full
/// strength rather than its `0.95` — there is no hover circle here to share the cue.
///
/// Read directly by the surfaces that cannot mount `inlineActionButtonStyle(foregroundColor:)`:
/// `PullRequestResolvedThreadHeader`, whose label carries three tints at once, and the AppKit
/// `AppKitReviewProposalCommentJumpButton`, which drives its `alphaValue` from these.
enum InlineActionButtonOpacity {
    static let active: Double = 1
    static let disabled: Double = 0.6

    /// The resting fade is the whole cost of this style: it takes "Resolve conversation" from
    /// 3.10:1 against its card to 2.34:1, both already under WCAG AA because macOS's own
    /// secondary label is. Increase Contrast therefore turns the fade *off* rather than softening
    /// it — someone who asked the system for maximum contrast is better served by a readable
    /// label than by a hover cue, and this style's hover simply becomes a no-op for them.
    ///
    /// Callers pass whichever spelling their framework exposes for that one setting:
    /// `\.colorSchemeContrast` in SwiftUI, `accessibilityDisplayShouldIncreaseContrast` in AppKit.
    static func resting(increasesContrast: Bool) -> Double {
        increasesContrast ? active : fadedResting
    }

    private static let fadedResting: Double = 0.8
}

extension View {
    /// Hover and press chrome for a low-emphasis *text* affordance at `.font(.caption)`: a
    /// comment thread's Reply and Resolve conversation, and Show in Changes. The text-bearing
    /// sibling of `iconActionButtonStyle(.inline)` — same easing, same `InlineActionButtonOpacity`
    /// ramp — but the label itself is the feedback. A fill sized to "Resolve conversation" would
    /// be a slab beside the caption text it rides with, where the icon family's circle is not.
    ///
    /// It draws no shape and adds no padding, so adopting it moves nothing in a caller's layout.
    /// The tint belongs here rather than in a call-site `foregroundStyle`, which would freeze
    /// through hover and disabled; octicons render as template images, so one tint alpha reaches
    /// the glyph and the label together.
    func inlineActionButtonStyle(foregroundColor: Color) -> some View {
        buttonStyle(InlineActionButtonStyle(foregroundColor: foregroundColor))
    }
}

private struct InlineActionButtonStyle: ButtonStyle {
    let foregroundColor: Color

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        InlineActionButtonBody(
            configuration: configuration,
            isEnabled: isEnabled,
            foregroundColor: foregroundColor
        )
    }
}

/// Extracted from the `ButtonStyle` so it can own an `@State` hover flag.
///
/// Carries neither the icon family's `scaleEffect` nor its focus ring: `ProminentActionButtonBody`,
/// the other text-bearing style, has neither, and a caption label scaling to 0.97 reads as a wobble
/// rather than a press.
private struct InlineActionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isEnabled: Bool
    let foregroundColor: Color

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(foregroundColor.opacity(opacity))
            // The gap between glyph and label is part of the control, not a hole in it.
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }

    /// Press brightens even without hover, because trackpad and keyboard activation both press
    /// while the pointer is elsewhere.
    private var opacity: Double {
        guard isEnabled else {
            return InlineActionButtonOpacity.disabled
        }

        if isHovering || configuration.isPressed {
            return InlineActionButtonOpacity.active
        }

        return InlineActionButtonOpacity.resting(increasesContrast: colorSchemeContrast == .increased)
    }
}
