import AppKit
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
let transcriptToolIconTextSpacing: CGFloat = 24
let transcriptToolLeadingTextSpacing = transcriptToolIconTextSpacing - transcriptToolIconFrameSize
let toolApprovalSummaryTopSpacing: CGFloat = 8
let toolApprovalSummaryLineSpacing: CGFloat = 2
let approvalCommandChipCornerRadius: CGFloat = 4
let approvalCommandChipHPadding: CGFloat = 3
let approvalCommandChipVPadding: CGFloat = 1
let toolApprovalActionsTopSpacing: CGFloat = 12
let transcriptToolRowVerticalPadding: CGFloat = 4
let transcriptInlineToolRowVerticalPadding: CGFloat = 2
let transcriptToolExpandedContentTopSpacing: CGFloat = 8
let toolExpandedContentBottomSpacing: CGFloat = 8
let transcriptToolNestedTopSpacing: CGFloat = 4
let transcriptToolNestedRowSpacing: CGFloat = 2
let transcriptToolElbowGap: CGFloat = 4
let transcriptInlineToolRowColor = NSColor(name: nil, dynamicProvider: { appearance in
    switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
        return NSColor.secondaryLabelColor.resolved(for: appearance)
    default:
        return NSColor.secondaryLabelColor.resolved(for: appearance)
    }
})
let inlineToolRowHoverAlphaMultiplier: CGFloat = 1.2
func transcriptInlineToolRowForegroundColor(isHovered: Bool) -> NSColor {
    guard isHovered else {
        return transcriptInlineToolRowColor
    }
    return NSColor(name: nil, dynamicProvider: { appearance in
        let resolved = transcriptInlineToolRowColor.resolved(for: appearance)
        return resolved.withAlphaComponent(min(resolved.alphaComponent * inlineToolRowHoverAlphaMultiplier, 1))
    })
}
let transcriptScrollLeadingInset: CGFloat = 20
let transcriptScrollTrailingInset: CGFloat = 21
let transcriptToolConnectorOpacity: Double = 0.28
let transcriptToolDetailLeadingInset = transcriptToolIconFrameSize + transcriptToolLeadingTextSpacing
// Keep the parent proposal on the narrow side for wrapped tool output.
// The output blocks inset their own trailing chrome by the remaining 5pt so the
// visible edge lands at 44pt without rewrapping text.
let transcriptToolDetailTrailingInset = transcriptToolDetailLeadingInset - 5
private let transcriptBubblePreferredWidthRatio: CGFloat = 2 / 3
private let transcriptBubbleMinimumPreferredWidth: CGFloat = 640
private let transcriptBubbleCompactTrailingInset: CGFloat = 24
private let inlineToolRowGap: CGFloat = 3

struct TranscriptInlineToolRowMetrics: Equatable {
    let leadingIconSize: CGFloat
    let statusIconSize: CGFloat
    let controlSize: CGFloat
    let iconTextSpacing: CGFloat
    let textStatusSpacing: CGFloat

    var leadingTextInset: CGFloat {
        controlSize + iconTextSpacing
    }

    var detailLeadingInset: CGFloat {
        leadingTextInset
    }

    var detailTrailingInset: CGFloat {
        max(detailLeadingInset - 5, 0)
    }

    func directDetailLeadingInset(showsLeadingIcon: Bool) -> CGFloat {
        showsLeadingIcon ? detailLeadingInset : 0
    }
}

func transcriptInlineToolRowMetrics(for typography: TranscriptTypography) -> TranscriptInlineToolRowMetrics {
    let baseIndicatorSize = typography.size(for: .inlineToolIndicator)
    let leadingIconSize = baseIndicatorSize + 2
    let statusIconSize = max(baseIndicatorSize - 2, 8)
    return TranscriptInlineToolRowMetrics(
        leadingIconSize: leadingIconSize,
        statusIconSize: statusIconSize,
        controlSize: ceil(max(leadingIconSize, statusIconSize) + 2),
        iconTextSpacing: inlineToolRowGap,
        textStatusSpacing: inlineToolRowGap
    )
}

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
