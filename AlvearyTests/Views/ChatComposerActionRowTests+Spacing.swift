import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testWideRowUsesRequestedVisibleSpacingWithContextIndicator() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                selectedPermissionMode: "auto",
                selectedUseWorktree: true,
                usageSummary: ConversationUsageSummary(
                    contextUsedTokens: 10_000,
                    contextWindowSize: 100_000,
                    totalCostUsd: 0.12,
                    hasReportedCost: true,
                    hasReportedUsage: true,
                    isUsingCachedContextWindow: false
                )
            )
        )

        row.layoutSubtreeIfNeeded()

        let actionButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertEqual(visibleGap(in: row, from: row.plusButton, to: row.permissionButton), 20, accuracy: 1)
        XCTAssertEqual(visibleGap(in: row, from: row.permissionButton, to: row.worktreeButton), 16, accuracy: 1)
        XCTAssertEqual(visibleGap(in: row, from: row.contextIndicatorView, to: row.reasoningButton), 12, accuracy: 1)
        XCTAssertEqual(visibleGap(in: row, from: row.reasoningButton, to: actionButton), 16, accuracy: 1)
    }

    func testWideRowUsesRequestedVisibleSpacingWithoutContextIndicator() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        row.configure(makeConfiguration(mode: .idle))

        row.layoutSubtreeIfNeeded()

        let actionButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertNil(row.contextIndicatorView.superview)
        XCTAssertEqual(visibleGap(in: row, from: row.plusButton, to: row.permissionButton), 20, accuracy: 1)
        XCTAssertEqual(visibleGap(in: row, from: row.permissionButton, to: row.worktreeButton), 16, accuracy: 1)
        XCTAssertEqual(visibleGap(in: row, from: row.reasoningButton, to: actionButton), 16, accuracy: 1)
    }

    func testWideRowUsesRequestedVisibleSpacingWhenPermissionButtonIsUnavailable() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        row.configure(makeConfiguration(mode: .idle, supportedPermissionModes: []))

        row.layoutSubtreeIfNeeded()

        XCTAssertNil(row.permissionButton.superview)
        XCTAssertEqual(visibleGap(in: row, from: row.plusButton, to: row.worktreeButton), 20, accuracy: 1)
    }
}

private extension NSView {
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

@MainActor
private func visibleGap(in row: ChatComposerActionRowView, from leadingView: NSView, to trailingView: NSView) -> CGFloat {
    row.visibleFrameForTesting(for: trailingView, in: row).minX -
        row.visibleFrameForTesting(for: leadingView, in: row).maxX
}
