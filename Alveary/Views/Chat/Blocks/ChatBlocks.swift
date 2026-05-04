import CoreGraphics

let chatBubbleHorizontalPadding: CGFloat = 12
let chatBubbleCornerRadius: CGFloat = 12
let userBubbleMaxWidth: CGFloat = 640
let userBubbleLeadingClearance: CGFloat = 60
let chatBlockPadding: CGFloat = 14
/// Shared vertical rhythm for bubble-style chat surfaces.
let chatVerticalPadding: CGFloat = 10
let chatBlockCornerRadius: CGFloat = 12
let transcriptToolIconFrameSize: CGFloat = 16
let transcriptToolStatusFrameSize = transcriptToolIconFrameSize
let transcriptToolIconTextSpacing: CGFloat = 24
let transcriptToolLeadingTextSpacing = transcriptToolIconTextSpacing - transcriptToolIconFrameSize
let transcriptToolTextStatusSpacing = transcriptToolLeadingTextSpacing
let approvalCommandChipCornerRadius: CGFloat = 4
let approvalCommandChipHPadding: CGFloat = 3
let approvalCommandChipVPadding: CGFloat = 1
let toolApprovalSummaryTopSpacing: CGFloat = 8
let toolApprovalActionsTopSpacing: CGFloat = 12
let transcriptToolStatusSpinnerScale: CGFloat = 0.72
let transcriptToolRowVerticalPadding: CGFloat = 4
let transcriptToolExpandedContentTopSpacing: CGFloat = 8
let toolExpandedContentBottomSpacing: CGFloat = 8
let transcriptToolNestedTopSpacing: CGFloat = 8
let transcriptToolNestedRowSpacing: CGFloat = 6
let transcriptToolElbowGap: CGFloat = 10
let transcriptScrollLeadingInset: CGFloat = 20
let transcriptScrollTrailingInset: CGFloat = 21
let transcriptToolNestedRowLeadingInset = transcriptToolIconFrameSize + transcriptToolLeadingTextSpacing
let transcriptToolConnectorOpacity: Double = 0.45
let transcriptToolDetailLeadingInset = transcriptToolIconFrameSize + transcriptToolLeadingTextSpacing
// Keep the parent proposal on the narrow side for wrapped tool output.
// The output blocks inset their own trailing chrome by the remaining 5pt so the
// visible edge lands at 44pt without rewrapping text.
let transcriptToolDetailTrailingInset = transcriptToolDetailLeadingInset - 5
private let transcriptBubblePreferredWidthRatio: CGFloat = 2 / 3
private let transcriptBubbleMinimumPreferredWidth: CGFloat = 640
private let transcriptBubbleCompactTrailingInset: CGFloat = 24

/// Wide transcripts look better when inbound bubbles stop around two-thirds of the
/// available width, but once that cap would squeeze below a comfortable reading width
/// we stop shrinking and only yield when the window itself gets tighter. On compact
/// windows the cap bottoms out at the previous "near the trailing edge" behavior by
/// leaving a 24pt gutter.
func adaptiveTranscriptBubbleMaxWidth(for transcriptContentWidth: CGFloat) -> CGFloat {
    guard transcriptContentWidth > 0 else {
        return .infinity
    }

    let preferredWidth = transcriptContentWidth * transcriptBubblePreferredWidthRatio
    let compactWidth = max(transcriptContentWidth - transcriptBubbleCompactTrailingInset, 0)
    return min(compactWidth, max(preferredWidth, transcriptBubbleMinimumPreferredWidth))
}
