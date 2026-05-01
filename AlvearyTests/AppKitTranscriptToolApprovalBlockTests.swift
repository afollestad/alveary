@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptToolApprovalBlockTests: XCTestCase {
    func testPendingBashApprovalShowsTitleSummaryAndSessionModes() {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"git status --short"}"#),
                status: .pending
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Approve Bash command?"))
        XCTAssertTrue(block.renderedText.contains("git status --short"))
        XCTAssertTrue(block.renderedText.contains("Approve once"))
        XCTAssertTrue(block.renderedText.contains("Deny"))
        XCTAssertTrue(block.visiblePopUps.isEmpty)
        XCTAssertEqual(block.visibleSplitControls.first?.menu?.items.map(\.title), ["Approve once", "Approve exactly", "Approve group"])
    }

    func testPendingApprovalBubbleHugsShortContentBeforeMaxWidth() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 900, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"date"}"#),
                status: .pending,
                bubbleMaxWidth: 700
            )
        )
        block.layoutSubtreeIfNeeded()

        let bubble = try XCTUnwrap(block.descendants(of: AppKitFlippedDynamicColorView.self).first)

        XCTAssertLessThan(bubble.frame.width, 700)
        XCTAssertGreaterThan(bubble.frame.width, 260)
    }

    func testBatchApprovalIntersectsSessionScopesAndUsesPluralCopy() {
        let first = approval(toolUseId: "write-1", toolName: "Write", input: #"{"file_path":"/tmp/one.txt"}"#)
        let second = approval(toolUseId: "write-2", toolName: "Write", input: #"{"file_path":"/tmp/two.txt"}"#)
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(.init(approval: first, approvals: [first, second], status: .pending))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.renderedText.contains("Approve writing to files?"))
        XCTAssertTrue(block.renderedText.contains("/tmp/one.txt"))
        XCTAssertTrue(block.renderedText.contains("/tmp/two.txt"))
        XCTAssertTrue(block.visiblePopUps.isEmpty)
        XCTAssertEqual(block.visibleSplitControls.first?.menu?.items.map(\.title), ["Approve once", "Approve for session"])
    }

    func testSelectingSessionModeRoutesApproveCallback() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        var approvedOnce = false
        var approvedScope: ToolApprovalSessionScope?
        block.onApprove = { approvedOnce = true }
        block.onApproveForSession = { approvedScope = $0 }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"git status --short"}"#),
                status: .pending,
                selectedApprovalSelection: .sessionGroup
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertEqual(block.visibleSplitControls.first?.label(forSegment: 0), "Approve group")
        block.handleApprove()

        XCTAssertFalse(approvedOnce)
        XCTAssertEqual(approvedScope, .group)
    }

    func testSelectingSessionModeNotifiesSelectionCallback() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        var selected: ToolApprovalSelection?
        block.onSelectApprovalSelection = { selected = $0 }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"git status --short"}"#),
                status: .pending
            )
        )
        block.layoutSubtreeIfNeeded()

        let splitControl = try XCTUnwrap(block.visibleSplitControls.first)
        let menuItem = try XCTUnwrap(splitControl.menu?.items.first { $0.title == "Approve exactly" })
        let action = try XCTUnwrap(menuItem.action)
        _ = NSApp.sendAction(action, to: menuItem.target, from: menuItem)

        XCTAssertEqual(selected, .sessionExact)
        XCTAssertEqual(splitControl.label(forSegment: 0), "Approve exactly")
    }

    func testDenyCallbackIsDisabledWhenBlocked() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        var denied = false
        block.onDeny = { denied = true }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Read", input: #"{"file_path":"AGENTS.md"}"#),
                status: .pending,
                isBlocked: true
            )
        )
        block.layoutSubtreeIfNeeded()

        let denyButton = try XCTUnwrap(block.visibleButtons.first { $0.title == "Deny" })
        XCTAssertFalse(denyButton.isEnabled)
        block.handleDeny()
        XCTAssertFalse(denied)
    }

    func testSessionApprovalSplitControlIsDisabledWhenBlocked() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"git status --short"}"#),
                status: .pending,
                isBlocked: true
            )
        )
        block.layoutSubtreeIfNeeded()

        let splitControl = try XCTUnwrap(block.visibleSplitControls.first)
        XCTAssertFalse(splitControl.isEnabled)
        XCTAssertTrue(block.visiblePopUps.isEmpty)
    }

    func testResolvedSessionStateHidesOppositeAction() {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"git status --short"}"#),
                status: .approvedForSessionGroup
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertEqual(block.visibleButtons.map(\.title), ["Approved group"])
        XCTAssertTrue(block.visiblePopUps.isEmpty)
        XCTAssertTrue(block.visibleSplitControls.isEmpty)
    }

    func testDeniedApprovalMovesIntoPendingApprovalSlot() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let window = NSWindow(contentRect: block.frame, styleMask: [], backing: .buffered, defer: false)
        window.contentView?.addSubview(block)
        let configuration = AppKitTranscriptToolApprovalBlockView.Configuration(
            approval: approval(toolName: "Bash", input: #"{"command":"date"}"#),
            status: .pending
        )
        block.configure(configuration)
        block.layoutSubtreeIfNeeded()
        let pendingApprove = try XCTUnwrap(block.visibleSplitControls.first)
        let pendingDeny = try XCTUnwrap(block.visibleButtons.first { $0.title == "Deny" })
        let pendingApproveMinX = pendingApprove.frame.minX
        let pendingDenyMinX = pendingDeny.frame.minX
        XCTAssertGreaterThan(pendingDeny.frame.minX, pendingApprove.frame.maxX)

        block.configure(.init(approval: configuration.approval, status: .denied))
        block.layoutSubtreeIfNeeded()

        let denied = try XCTUnwrap(block.visibleButtons.first { $0.title == "Denied" })
        let approvalPlaceholder = try XCTUnwrap(block.descendants(of: NSSegmentedControl.self).first)
        XCTAssertEqual(denied.frame.minX, pendingDenyMinX, accuracy: 0.5)
        XCTAssertLessThan(approvalPlaceholder.alphaValue, 0.01)

        let animationFrames = try XCTUnwrap(block.denySlotAnimationFramesForTesting)
        XCTAssertEqual(animationFrames.from.minX, pendingDenyMinX, accuracy: 0.5)
        XCTAssertEqual(animationFrames.to.minX, pendingApproveMinX, accuracy: 0.5)
        XCTAssertTrue(block.didDeferDenySlotAnimationForTesting)
        let activeTargetFrame = try XCTUnwrap(block.activeDenyTargetFrameForTesting)
        XCTAssertEqual(activeTargetFrame.minX, pendingApproveMinX, accuracy: 0.5)

        block.layoutSubtreeIfNeeded()
        XCTAssertEqual(denied.frame.minX, pendingDenyMinX, accuracy: 0.5)

        let placeholderFrames = try XCTUnwrap(block.approvePlaceholderFramesForTesting)
        XCTAssertEqual(placeholderFrames.from.minX, pendingApproveMinX, accuracy: 0.5)
        XCTAssertGreaterThan(placeholderFrames.to.minX, placeholderFrames.from.minX)
        XCTAssertTrue(block.didDeferPlaceholderAnimationForTesting)
    }

    func testResolvedApprovalButtonsKeepSymbolsTintedWithButtonText() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"date"}"#),
                status: .approved
            )
        )
        block.layoutSubtreeIfNeeded()

        let approved = try XCTUnwrap(block.visibleButtons.first { $0.title == "Approved" } as? AppKitTranscriptApprovalButton)
        XCTAssertEqual(approved.symbolNameForTesting, "checkmark")
        XCTAssertNil(approved.image)

        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"date"}"#),
                status: .denied
            )
        )
        block.layoutSubtreeIfNeeded()

        let denied = try XCTUnwrap(block.visibleButtons.first { $0.title == "Denied" } as? AppKitTranscriptApprovalButton)
        XCTAssertEqual(denied.symbolNameForTesting, "xmark")
        XCTAssertNil(denied.image)
        XCTAssertFalse(denied.isEnabled)
    }

    func testCommandSummaryChipHugsCommandText() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 620, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"date"}"#),
                status: .pending
            )
        )
        block.layoutSubtreeIfNeeded()

        let summary = try XCTUnwrap(block.descendants(of: AppKitTranscriptApprovalSummaryLineView.self).first)
        let chip = try XCTUnwrap(summary.descendants(of: NSTextField.self).first)

        XCTAssertEqual(summary.frame.width, summary.naturalWidth, accuracy: 1)
        XCTAssertLessThan(chip.frame.width, 80)
    }

    func testSummaryGrowthInvalidatesHeight() {
        let block = AppKitTranscriptToolApprovalBlockView()
        var invalidated = false
        block.onHeightInvalidated = {
            invalidated = true
        }
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let first = approval(toolUseId: "write-1", toolName: "Write", input: #"{"file_path":"/tmp/one.txt"}"#)
        block.configure(.init(approval: first, status: .pending))
        block.layoutSubtreeIfNeeded()
        let singleHeight = block.intrinsicContentSize.height
        invalidated = false

        let second = approval(toolUseId: "write-2", toolName: "Write", input: #"{"file_path":"/tmp/two.txt"}"#)
        let third = approval(toolUseId: "write-3", toolName: "Write", input: #"{"file_path":"/tmp/three.txt"}"#)
        block.configure(.init(approval: first, approvals: [first, second, third], status: .pending))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(block.intrinsicContentSize.height, singleHeight)
    }

    func testNarrowUnsupportedApprovalKeepsActionsBelowSummary() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 150, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Read", input: #"{"file_path":"AGENTS.md"}"#),
                status: .pending
            )
        )
        block.layoutSubtreeIfNeeded()

        let summary = try XCTUnwrap(block.descendants(of: AppKitTranscriptApprovalSummaryLineView.self).first)
        let approve = try XCTUnwrap(block.visibleButtons.first { $0.title == "Approve" })
        XCTAssertGreaterThan(approve.frame.minY, summary.frame.maxY)
    }

    func testApprovedApprovalLayoutKeepsHeaderSummaryAndActionTopDown() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"wc -c /tmp/file.txt"}"#),
                status: .approved
            )
        )
        block.layoutSubtreeIfNeeded()

        let title = try XCTUnwrap(block.descendants(of: NSTextField.self).first { $0.stringValue == "Approve Bash command?" })
        let summary = try XCTUnwrap(block.descendants(of: AppKitTranscriptApprovalSummaryLineView.self).first)
        let approved = try XCTUnwrap(block.visibleButtons.first { $0.title == "Approved" })

        XCTAssertGreaterThan(summary.frame.minY, title.frame.maxY)
        XCTAssertGreaterThan(approved.frame.minY, summary.frame.maxY)
    }

    func testApprovalButtonsReserveSpaceForIconAndTitle() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Read", input: #"{"file_path":"AGENTS.md"}"#),
                status: .pending
            )
        )
        block.layoutSubtreeIfNeeded()

        let approve = try XCTUnwrap(block.visibleButtons.first { $0.title == "Approve" })

        XCTAssertEqual(approve.imagePosition, .imageLeading)
        XCTAssertFalse(approve.isBordered)
        XCTAssertEqual(approve.frame.height, 24, accuracy: 0.5)
        XCTAssertGreaterThan(approve.frame.width, (approve.title as NSString).size(withAttributes: [.font: approve.font as Any]).width + 20)
    }

    func testApprovalSplitControlUsesActionButtonHeight() throws {
        let block = AppKitTranscriptToolApprovalBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        block.configure(
            .init(
                approval: approval(toolName: "Bash", input: #"{"command":"date"}"#),
                status: .pending
            )
        )
        block.layoutSubtreeIfNeeded()

        let splitControl = try XCTUnwrap(block.visibleSplitControls.first)

        XCTAssertEqual(splitControl.frame.height, 24, accuracy: 0.5)
    }

    func testApprovalSplitControlChevronPreservesSymbolAspectRatio() throws {
        let splitControl = AppKitTranscriptApprovalSplitControl()
        let bounds = NSRect(x: 0, y: 0, width: 10, height: 10)

        let drawingRect = try XCTUnwrap(splitControl.symbolDrawingRectForTesting(symbolName: "chevron.down", in: bounds))

        XCTAssertLessThan(drawingRect.height, bounds.height)
        XCTAssertEqual(drawingRect.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(drawingRect.midY, bounds.midY, accuracy: 0.5)
    }
}

private func approval(
    sessionId: String = "session-1",
    toolUseId: String = "tool-1",
    toolName: String,
    input: String
) -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: sessionId,
        toolUseId: toolUseId,
        toolName: toolName,
        toolInput: input
    )
}

private extension NSView {
    var renderedText: String {
        let fields = descendants(of: NSTextField.self).map(\.stringValue)
        let buttons = visibleButtons.map(\.title)
        let splitControls = visibleSplitControls.compactMap { $0.label(forSegment: 0) }
        let popUps = visiblePopUps.flatMap(\.itemTitles)
        return (fields + buttons + splitControls + popUps).joined(separator: "\n")
    }

    var visibleButtons: [NSButton] {
        descendants(of: NSButton.self).filter { !$0.isHidden && $0.alphaValue > 0.01 }
    }

    var visiblePopUps: [NSPopUpButton] {
        descendants(of: NSPopUpButton.self).filter { !$0.isHidden && $0.alphaValue > 0.01 }
    }

    var visibleSplitControls: [NSSegmentedControl] {
        descendants(of: NSSegmentedControl.self).filter { !$0.isHidden && $0.alphaValue > 0.01 }
    }

    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
