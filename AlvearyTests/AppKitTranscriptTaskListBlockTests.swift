@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptTaskListBlockTests: XCTestCase {
    func testTaskListOrdersRowsAndUsesActiveForm() throws {
        let block = configuredBlock(tasks: mixedTasks())

        let taskTexts = block.taskTextFields.map(\.stringValue)
        XCTAssertEqual(taskTexts, ["Refreshing snapshots", "Run focused UI tests", "Fix autocomplete warning"])
    }

    func testTaskListPreservesInputOrderWithinSameStatus() {
        let tasks = [
            task("Pick a fake task C", .completed),
            task("Pick a fake task B", .completed),
            task("Pick a fake task A", .completed)
        ]

        let block = configuredBlock(tasks: tasks)

        XCTAssertEqual(
            block.taskTextFields.map(\.stringValue),
            ["Pick a fake task C", "Pick a fake task B", "Pick a fake task A"]
        )
        XCTAssertEqual(tasks.taskListPresentationOrder.map(\.content), ["Pick a fake task C", "Pick a fake task B", "Pick a fake task A"])
    }

    func testCompletedTaskReusesCheckedRowAndMovesToSortedPosition() throws {
        let block = AppKitTranscriptTaskListBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let window = NSWindow(contentRect: block.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = block
        block.configure(.init(tasks: [
            task("Task A", .pending),
            task("Task B", .pending)
        ]))
        block.layoutSubtreeIfNeeded()
        let firstTaskRow = try XCTUnwrap(block.taskRowForTesting(id: "Task A"))
        let firstTaskStartY = firstTaskRow.frame.minY

        block.configure(.init(tasks: [
            task("Task A", .completed),
            task("Task B", .pending)
        ]))

        XCTAssertTrue(firstTaskRow === block.taskRowForTesting(id: "Task A"))
        XCTAssertNotNil(firstTaskRow.taskTextFields.first?.attributedStringValue.attribute(.strikethroughStyle, at: 0, effectiveRange: nil))
        XCTAssertTrue(block.hasPendingRowAnimationsForTesting)

        block.layoutSubtreeIfNeeded()

        XCTAssertEqual(block.taskRowIDsForTesting, ["Task B", "Task A"])
        XCTAssertEqual(firstTaskRow.frame.minY, firstTaskStartY)
        let targetFrame = try XCTUnwrap(block.activeRowAnimationTargetFrameForTesting(id: "Task A"))
        XCTAssertGreaterThan(targetFrame.minY, firstTaskStartY)
        XCTAssertFalse(block.hasPendingRowAnimationsForTesting)
        window.contentView = nil
    }

    func testTaskListPositionsTitleAboveRows() throws {
        let block = configuredBlock(tasks: mixedTasks())
        let title = try XCTUnwrap(block.descendants(of: NSTextField.self).first { $0.stringValue == "Tasks" })
        let firstTask = try XCTUnwrap(block.taskTextFields.first)
        let titleFrame = block.convert(title.frame, from: title.superview)
        let firstTaskFrame = block.convert(firstTask.frame, from: firstTask.superview)

        XCTAssertLessThan(titleFrame.minY, firstTaskFrame.minY)
    }

    func testStatusIndicatorsUseFixedSlotsAndAppKitProgress() throws {
        let block = configuredBlock(tasks: mixedTasks())

        let spinner = try XCTUnwrap(block.descendants(of: AppKitStatusIndicatorSpinner.self).first)
        XCTAssertEqual(spinner.frame.size, NSSize(width: 12, height: 12))
        XCTAssertEqual(spinner.accessibilityLabel(), "In progress")

        let imageViews = block.descendants(of: NSImageView.self)
        XCTAssertEqual(imageViews.count, 2)
        XCTAssertTrue(imageViews.allSatisfy { $0.frame.size == NSSize(width: 16, height: 16) })
    }

    func testTaskRowsUseCompactVerticalSpacing() {
        let block = configuredBlock(tasks: mixedTasks())

        XCTAssertEqual(block.rowSpacingForTesting, 10)
    }

    func testPendingRowAnimationSurvivesDetachedRelayout() throws {
        let block = AppKitTranscriptTaskListBlockView()
        block.frame = NSRect(x: 0, y: 0, width: 520, height: 1_000)
        let window = NSWindow(contentRect: block.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = block
        block.configure(.init(tasks: [
            task("Task A", .pending),
            task("Task B", .pending)
        ]))
        block.layoutSubtreeIfNeeded()
        let firstTaskRow = try XCTUnwrap(block.taskRowForTesting(id: "Task A"))

        window.contentView = nil
        block.configure(.init(tasks: [
            task("Task A", .completed),
            task("Task B", .pending)
        ]))
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(block.hasPendingRowAnimationsForTesting)

        window.contentView = block
        block.layoutSubtreeIfNeeded()

        XCTAssertEqual(block.taskRowIDsForTesting, ["Task B", "Task A"])
        XCTAssertTrue(firstTaskRow === block.taskRowForTesting(id: "Task A"))
        XCTAssertNotNil(block.activeRowAnimationTargetFrameForTesting(id: "Task A"))
        XCTAssertFalse(block.hasPendingRowAnimationsForTesting)
        window.contentView = nil
    }

    func testCompletedTaskUsesSecondaryStrikethroughText() throws {
        let block = configuredBlock(tasks: mixedTasks())
        let field = try XCTUnwrap(block.taskTextFields.first { $0.stringValue == "Fix autocomplete warning" })
        let attributes = field.attributedStringValue.attributes(at: 0, effectiveRange: nil)

        XCTAssertEqual(attributes[.foregroundColor] as? NSColor, NSColor.secondaryLabelColor)
        XCTAssertNotNil(attributes[.strikethroughStyle])
    }

    func testBubbleHugsShortContentBeforeConfiguredMaxWidth() {
        let block = configuredBlock(tasks: mixedTasks(), blockWidth: 600, bubbleMaxWidth: 480)

        XCTAssertLessThan(block.subviews.first?.frame.width ?? 0, 320)
    }

    func testBubbleCapsLongContentAtConfiguredMaxWidth() {
        let block = configuredBlock(
            tasks: [
                task(
                    "This task title is deliberately long enough that its natural width exceeds the configured maximum width.",
                    .pending
                )
            ],
            blockWidth: 600,
            bubbleMaxWidth: 320
        )

        XCTAssertEqual(block.subviews.first?.frame.width, 320)
    }

    func testCompletedLongTaskWrapsWhenCappedByConfiguredMaxWidth() throws {
        let block = configuredBlock(
            tasks: [
                task(
                    "Verify all script files are referenced in the static bundle manifest before publishing.",
                    .completed
                )
            ],
            blockWidth: 360,
            bubbleMaxWidth: 320
        )
        let field = try XCTUnwrap(block.taskTextFields.first)

        XCTAssertEqual(block.subviews.first?.frame.width, 320)
        XCTAssertTrue(field.cell?.wraps ?? false)
        XCTAssertFalse(field.cell?.isScrollable ?? true)
        XCTAssertGreaterThan(field.frame.height, 20)
    }

    func testHeightInvalidatesWhenTaskTextGrows() {
        let block = AppKitTranscriptTaskListBlockView()
        var invalidated = false
        block.onHeightInvalidated = {
            invalidated = true
        }
        block.frame = NSRect(x: 0, y: 0, width: 260, height: 1_000)
        block.configure(.init(tasks: [task("Short", .pending)], bubbleMaxWidth: 240))
        block.layoutSubtreeIfNeeded()
        let shortHeight = block.intrinsicContentSize.height
        invalidated = false

        block.configure(
            .init(
                tasks: [
                    task(
                        "This pending task has enough copy to wrap across multiple lines in the AppKit row layout.",
                        .pending
                    )
                ],
                bubbleMaxWidth: 240
            )
        )
        block.layoutSubtreeIfNeeded()

        XCTAssertTrue(invalidated)
        XCTAssertGreaterThan(block.intrinsicContentSize.height, shortHeight)
    }

    private func configuredBlock(
        tasks: [TaskEntry],
        blockWidth: CGFloat = 520,
        bubbleMaxWidth: CGFloat = 480
    ) -> AppKitTranscriptTaskListBlockView {
        let block = AppKitTranscriptTaskListBlockView()
        block.frame = NSRect(x: 0, y: 0, width: blockWidth, height: 1_000)
        block.configure(.init(tasks: tasks, bubbleMaxWidth: bubbleMaxWidth))
        block.layoutSubtreeIfNeeded()
        return block
    }

    private func mixedTasks() -> [TaskEntry] {
        [
            task("Run focused UI tests", .pending),
            task("Fix autocomplete warning", .completed),
            task("Refresh snapshots", .inProgress, activeForm: "Refreshing snapshots")
        ]
    }

    private func task(_ content: String, _ status: TaskEntry.Status, activeForm: String? = nil) -> TaskEntry {
        TaskEntry(id: content, content: content, activeForm: activeForm, status: status)
    }
}

private extension NSView {
    var taskTextFields: [NSTextField] {
        descendants(of: NSTextField.self).filter { $0.stringValue != "Tasks" }
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
