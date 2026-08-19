import SwiftUI

/// The blue dot a collapsed sidebar container shows while it hides a thread waiting on the user.
///
/// It stands in for the `.waitingForUser` dot on the row the collapse hid, so it takes the same blue
/// from **Status Dot Colors** in `Alveary/Views/AGENTS.md` — never another colour, and never the busy
/// spinner, which marks a state that resolves without the user.
///
/// Size and vertical placement are measured against the `.subheadline` title it trails, which on
/// macOS is 11pt: cap height 7.75, x-height 5.87, a 14pt line box, and a cap-height centre sitting
/// 0.28pt below the line-box centre.
///
/// - `diameter` is 6 — between x-height and cap height — rather than `SidebarThreadRow`'s 8. That dot
///   sits alone in a trailing column with no text to measure against; this one is read beside a word,
///   and 8 exceeds the cap height enough to look as tall as the capital letter.
/// - Vertical placement is the enclosing `HStack`'s plain `.center`. The 0.28pt gap between the two
///   centres is sub-pixel at 1x, so the dot already lands on the title's optical centre — do not add
///   an `alignmentGuide` or an `offset(y:)` correction.
/// - Both hosts stay taller than this dot regardless (the title's 14pt line box, the caret's 14pt
///   frame), so it can never drive row height.
struct SidebarWaitingAttentionDot: View {
    static let diameter: CGFloat = 6
    static let help = "Waiting for you"

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: Self.diameter, height: Self.diameter)
            .help(Self.help)
            // Both hosts combine their title cluster behind a single label, so the dot is announced
            // through `sidebarWaitingAttentionAccessibilityLabel` rather than as its own element.
            .accessibilityHidden(true)
    }
}

/// The label a collapsed container gives VoiceOver while `SidebarWaitingAttentionDot` is showing, so
/// a section header and a project row phrase it identically.
func sidebarWaitingAttentionAccessibilityLabel(_ base: String, hidesWaitingThread: Bool) -> String {
    hidesWaitingThread ? "\(base), waiting for you" : base
}
