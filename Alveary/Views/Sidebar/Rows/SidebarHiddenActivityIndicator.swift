import SwiftUI

/// The indicator a collapsed sidebar container shows for the thread its collapse hid.
///
/// It stands in for that row's own status indicator, so it takes both its colour and its shape
/// from **Status Dot Colors** in `Alveary/Views/AGENTS.md`: blue dot for `.waitingForUser`, red
/// dot for a failed one, the shared neutral ring for a working thread. Never give the working case
/// a colour — the spinning shape is the signal.
///
/// Size and vertical placement are measured against the `.subheadline` title it trails, which on
/// macOS is 11pt: cap height 7.75, x-height 5.87, a 14pt line box, and a cap-height centre sitting
/// 0.28pt below the line-box centre.
///
/// - `diameter` is 6 — between x-height and cap height — rather than `SidebarThreadRow`'s 8. That
///   row's indicator sits alone in a trailing column with no text to measure against; this one is
///   read beside a word, and 8 exceeds the cap height enough to look as tall as the capital letter.
/// - **Every case occupies exactly `diameter`.** `StatusIndicatorSpinner` pins its own frame to the
///   diameter it is handed, so switching among them cannot resize the row or shift the title.
/// - Vertical placement is the enclosing `HStack`'s plain `.center`. The 0.28pt gap between the two
///   centres is sub-pixel at 1x, so it already lands on the title's optical centre — do not add an
///   `alignmentGuide` or an `offset(y:)` correction.
/// - Both hosts stay taller than this indicator regardless (the title's 14pt line box, the caret's
///   14pt frame), so it can never drive row height.
struct SidebarHiddenActivityIndicator: View {
    static let diameter: CGFloat = 6
    /// `StatusIndicatorSpinner`'s 1.5 scaled by this indicator's 6/8 diameter, so the ring keeps
    /// the same stroke-to-diameter proportion as the 8pt one it stands in for.
    private static let spinnerLineWidth: CGFloat = 1.5 * diameter / 8

    let activity: SidebarHiddenActivity

    var body: some View {
        indicator
            .frame(width: Self.diameter, height: Self.diameter)
            .help(Self.help(for: activity))
            // Both hosts combine their title cluster behind a single label, so this is announced
            // through `sidebarHiddenActivityAccessibilityLabel` rather than as its own element.
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var indicator: some View {
        switch activity {
        case .waitingForUser:
            Circle().fill(Color.blue)
        case .failed:
            Circle().fill(Color.red)
        case .working:
            StatusIndicatorSpinner(
                color: .secondary,
                diameter: Self.diameter,
                lineWidth: Self.spinnerLineWidth
            )
        }
    }

    static func help(for activity: SidebarHiddenActivity) -> String {
        switch activity {
        case .waitingForUser:
            return "Waiting for you"
        case .failed:
            return "Failed"
        case .working:
            return "Working"
        }
    }
}

/// The label a collapsed container gives VoiceOver while `SidebarHiddenActivityIndicator` is
/// showing, so a section header and a project row phrase it identically.
func sidebarHiddenActivityAccessibilityLabel(_ base: String, activity: SidebarHiddenActivity?) -> String {
    switch activity {
    case .none:
        return base
    case .waitingForUser:
        return "\(base), waiting for you"
    case .failed:
        return "\(base), failed"
    case .working:
        return "\(base), working"
    }
}
