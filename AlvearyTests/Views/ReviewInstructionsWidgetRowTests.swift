@preconcurrency import AppKit
import XCTest

@testable import Alveary

/// The card both instruction tools share: it reports rather than navigates, so clicking it
/// reveals the instructions in place instead of opening the pull request.
@MainActor
final class ReviewInstructionsWidgetRowTests: XCTestCase {
    private static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    private static let instructions = "Focus on correctness.\n\n## Pull request\n- Pull request: `octo/alpha#7`"

    func testALoadedCardNamesThePullRequestItIsReviewing() {
        let host = host(for: entry(status: .loaded, instructions: Self.instructions))

        XCTAssertTrue(labels(in: host).contains { $0.contains("Reviewing octo/alpha#7 with your instructions") })
    }

    func testARunningCardSaysItIsStillReading() {
        let host = host(for: entry(status: .running, instructions: nil, isComplete: false))

        XCTAssertTrue(labels(in: host).contains { $0.contains("Reading the review instructions") })
    }

    func testAFailedCardSaysTheInstructionsCouldNotBeRead() {
        let host = host(for: entry(status: .failed, instructions: nil, isError: true))

        XCTAssertTrue(labels(in: host).contains { $0.contains("Could not read the review instructions") })
    }

    /// The card is the disclosure control: pressing it reveals the instructions in place rather
    /// than navigating away from the review it is starting.
    func testPressingTheCardTogglesTheDisclosure() throws {
        let entry = entry(status: .loaded, instructions: Self.instructions)
        let host = host(for: entry)

        XCTAssertNil(entry.openableTarget)
        let card = try XCTUnwrap(pressableCard(in: host))
        XCTAssertEqual(card.accessibilityValue() as? String, "Collapsed")

        _ = card.accessibilityPerformPress()
        XCTAssertEqual(card.accessibilityValue() as? String, "Expanded")

        _ = card.accessibilityPerformPress()
        XCTAssertEqual(card.accessibilityValue() as? String, "Collapsed")
    }

    /// A running or failed call has nothing behind the caret, so the card stays inert.
    func testACardWithoutInstructionsIsNotPressable() {
        XCTAssertNil(pressableCard(in: host(for: entry(status: .running, instructions: nil, isComplete: false))))
        XCTAssertNil(pressableCard(in: host(for: entry(status: .failed, instructions: nil, isError: true))))
    }

    /// A landed read decides nothing, so it is settled the moment it returns — which is what
    /// gives the card its completed glyph instead of leaving it on the clock.
    func testALoadedCardIsSettledWithoutADecision() {
        XCTAssertTrue(entry(status: .loaded, instructions: Self.instructions).isSettledWithoutDecision)
        XCTAssertFalse(entry(status: .running, instructions: nil, isComplete: false).isSettledWithoutDecision)
    }

    /// Codex emits the plain-text fallback rather than structured content, and for these tools
    /// that text is the instructions.
    func testAPlainTextResultStillCarriesTheInstructions() {
        let content = ReviewInstructionsWidgetParsing.content(
            kind: .review,
            input: #"{"url":"https://github.com/octo/alpha/pull/7"}"#,
            output: Self.instructions,
            isError: false
        )

        XCTAssertEqual(content?.status, .loaded)
        XCTAssertEqual(content?.instructions, Self.instructions)
        XCTAssertEqual(content?.identifier, Self.pullRequest)
    }

    /// The card can name its pull request from the call's own argument, before the result lands.
    func testARunningCallNamesItsPullRequestFromTheInput() {
        let content = ReviewInstructionsWidgetParsing.content(
            kind: .review,
            input: #"{"url":"https://github.com/octo/alpha/pull/7"}"#,
            output: nil,
            isError: false
        )

        XCTAssertEqual(content?.status, .running)
        XCTAssertEqual(content?.identifier, Self.pullRequest)
    }

    /// The two kinds share every affordance, so only the sentence may differ — a card that said
    /// "Reviewing" while the agent was fixing things would describe the wrong work.
    func testTheAddressFeedbackCardNamesItsOwnWork() {
        let loaded = host(for: entry(kind: .addressFeedback, status: .loaded, instructions: Self.instructions))
        XCTAssertTrue(labels(in: loaded).contains {
            $0.contains("Addressing feedback on octo/alpha#7 with your instructions")
        })

        let running = host(for: entry(kind: .addressFeedback, status: .running, instructions: nil, isComplete: false))
        XCTAssertTrue(labels(in: running).contains { $0.contains("Reading the feedback instructions") })
    }

    /// Its card discloses the same way, so the second tool needs no view of its own.
    func testPressingTheAddressFeedbackCardTogglesTheDisclosure() throws {
        let entry = entry(kind: .addressFeedback, status: .loaded, instructions: Self.instructions)

        XCTAssertNil(entry.openableTarget)
        let card = try XCTUnwrap(pressableCard(in: host(for: entry)))
        XCTAssertEqual(card.accessibilityValue() as? String, "Collapsed")
        _ = card.accessibilityPerformPress()
        XCTAssertEqual(card.accessibilityValue() as? String, "Expanded")
    }

    private func entry(
        kind: ReviewInstructionsWidgetContent.Kind = .review,
        status: ReviewInstructionsWidgetContent.Status,
        instructions: String?,
        isComplete: Bool = true,
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        let toolName = kind == .review
            ? PullRequestHostToolCatalog.reviewInstructionsToolName
            : PullRequestHostToolCatalog.addressFeedbackInstructionsToolName
        return HostToolWidgetEntry(
            id: "call-1",
            toolName: HostToolTranscriptCatalog.toolName(toolName),
            content: .pullRequestReviewInstructions(
                ReviewInstructionsWidgetContent(
                    kind: kind,
                    identifier: Self.pullRequest,
                    instructions: instructions,
                    status: status
                )
            ),
            isComplete: isComplete,
            isError: isError
        )
    }

    private func host(for entry: HostToolWidgetEntry) -> NSView {
        let view = AppKitTranscriptHostToolWidgetRowView(frame: .zero)
        view.configure(.init(entry: entry, bubbleMaxWidth: 480))
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 200)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func pressableCard(in view: NSView) -> NSView? {
        if view.accessibilityRole() == .button {
            return view
        }
        for subview in view.subviews {
            if let card = pressableCard(in: subview) {
                return card
            }
        }
        return nil
    }

    private func labels(in view: NSView) -> [String] {
        var found: [String] = []
        if let label = view.accessibilityLabel() {
            found.append(label)
        }
        if let field = view as? NSTextField {
            found.append(field.stringValue)
        }
        for subview in view.subviews {
            found.append(contentsOf: labels(in: subview))
        }
        return found
    }
}
