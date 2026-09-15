import AppKit
import Testing

@testable import Alveary

@MainActor
extension ReviewTeamRunWidgetTests {
    @Test
    func `pressing a reviewer opens that reviewers activity after an update`() throws {
        let view = AppKitReviewTeamRunWidgetView()
        var run = failedRun()
        view.configure(.init(run: run, typography: TranscriptTypography()))
        run.generation += 1
        view.configure(.init(run: run, typography: TranscriptTypography()))
        let receipt = ReviewRunActionReceipt()
        let observer = NotificationCenter.default.addObserver(forName: .reviewTeamDetailsRequested, object: view, queue: .main) { note in
            let selectedRun = note.userInfo?["run"] as? ReviewTeamRun
            let reviewerID = note.userInfo?["reviewerID"] as? String
            MainActor.assumeIsolated {
                receipt.run = selectedRun
                receipt.reviewerID = reviewerID
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let rows = reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: view)
        #expect(rows.map(\.reviewerID) == run.team.map(\.id))
        for row in rows {
            #expect(row.accessibilityRole() == .button)
            #expect(row.accessibilityPerformPress())
            #expect(receipt.run == run)
            #expect(receipt.reviewerID == row.reviewerID)
        }
        try #require(reviewTeamDescendants(of: NSButton.self, in: view).first { $0.title == "Run details" }).performClick(nil)
        #expect(receipt.run == run)
        #expect(receipt.reviewerID == nil)
    }

    @Test
    func `transcript updates preserve reviewer keyboard focus`() throws {
        var run = pausedRun(phase: .crossChecking)
        let view = AppKitTranscriptHostToolWidgetRowView()
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 700, height: 1_000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer {
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
        }
        view.configure(.init(entry: compactWidgetEntry(run), bubbleMaxWidth: 700))
        view.layoutSubtreeIfNeeded()
        let reviewer = try #require(reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: view).first)
        #expect(window.makeFirstResponder(reviewer))

        run.generation += 1
        view.configure(.init(entry: compactWidgetEntry(run), bubbleMaxWidth: 700))
        let updated = try #require(reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: view).first)
        #expect(window.firstResponder === updated)
        #expect(updated.reviewerID == reviewer.reviewerID)

        view.configure(.init(entry: compactWidgetEntry(run), bubbleMaxWidth: 360, typography: largeTypography()))
        let restyled = try #require(reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: view).first)
        #expect(window.firstResponder === restyled)
        #expect(restyled.reviewerID == reviewer.reviewerID)
    }

    @Test
    func `active and terminal reviewers expose semantic visual states`() throws {
        var run = failedRun()
        let lead = try #require(run.team.first { $0.id == "lead" })
        let peer = try #require(run.team.first { $0.id == "peer" })
        #expect(ReviewTeamRunPresentation.status(for: peer, in: run).visualState == .failed)
        #expect(ReviewTeamRunPresentation.status(for: lead, in: run).visualState == .completed)

        run.failures = [:]
        run.phase = .inspecting
        #expect(ReviewTeamRunPresentation.status(for: peer, in: run).visualState == .working)
        run.phase = .cancelled
        #expect(ReviewTeamRunPresentation.status(for: peer, in: run).visualState == .idle)
    }

    @Test(arguments: [CGFloat(220), CGFloat(360)])
    func `narrow paused card keeps every reviewer and action within its width`(width: CGFloat) throws {
        let run = pausedRun(phase: .crossChecking)
        let view = AppKitTranscriptHostToolWidgetRowView()
        let entry = compactWidgetEntry(run)
        view.frame = NSRect(x: 0, y: 0, width: 760, height: 1_000)
        view.configure(.init(entry: entry, bubbleMaxWidth: 760))
        view.layoutSubtreeIfNeeded()
        let wideHeight = view.intrinsicContentSize.height
        let retry = try #require(reviewTeamDescendants(of: NSButton.self, in: view).first { $0.title == "Retry failed reviewers" })
        let retryHelp = try #require(retry.toolTip)
        #expect(retryHelp.contains("Reuse completed reports"))

        view.frame.size.width = width
        view.configure(.init(entry: entry, bubbleMaxWidth: width, typography: largeTypography()))
        view.layoutSubtreeIfNeeded()

        #expect(view.intrinsicContentSize.height > wideHeight)
        let reviewers = reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: view)
        #expect(reviewers.count == run.team.count)
        let actions = reviewTeamDescendants(of: NSButton.self, in: view).filter { !$0.isHidden && !$0.title.isEmpty }
        #expect(actions.contains { $0.accessibilityLabel() == "Continue with majority" })
        let narrowRetry = try #require(actions.first { $0.accessibilityLabel() == "Retry failed reviewers" })
        #expect(narrowRetry.toolTip?.contains(retryHelp) == true)
        for control in reviewers.map({ $0 as NSView }) + actions.map({ $0 as NSView }) {
            let frame = control.convert(control.bounds, to: view)
            #expect(frame.width > 0 && frame.height > 0)
            #expect(frame.minX >= -1 && frame.maxX <= view.bounds.width + 1)
            #expect(frame.maxY <= view.intrinsicContentSize.height + 1)
        }
        let actionLines = Set(actions.map { Int($0.convert($0.bounds, to: view).minY.rounded()) })
        #expect(actionLines.count > 1)

        view.frame.size.width = 760
        view.configure(.init(entry: entry, bubbleMaxWidth: 760, typography: largeTypography()))
        view.layoutSubtreeIfNeeded()
        let restoredActions = reviewTeamDescendants(of: NSButton.self, in: view)
        for title in ["Run details", "Cancel review", "Retry failed reviewers", "Continue with majority"] {
            let action = try #require(restoredActions.first { $0.accessibilityLabel() == title })
            #expect(action.title == title)
            if title == "Retry failed reviewers" { #expect(action.toolTip == retryHelp) }
        }
    }

    @Test
    func `not proposed expansion survives width typography and run updates`() throws {
        var run = pausedRun(phase: .crossChecking)
        run.phase = .staged
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.frame = NSRect(x: 0, y: 0, width: 700, height: 1_200)
        view.configure(.init(entry: compactWidgetEntry(run), bubbleMaxWidth: 700))
        view.layoutSubtreeIfNeeded()
        let collapsedHeight = view.intrinsicContentSize.height
        try #require(reviewTeamDescendants(of: AppKitTranscriptHeaderToggleButton.self, in: view).first {
            $0.title == "Show 1 not proposed"
        }).performClick(nil)
        view.layoutSubtreeIfNeeded()
        #expect(view.intrinsicContentSize.height > collapsedHeight)
        let evidence = try #require(reviewTeamDescendants(of: AppKitReviewProposalVoteEvidenceView.self, in: view).first)
        try #require(reviewTeamDescendants(of: AppKitTranscriptHeaderToggleButton.self, in: evidence).first).performClick(nil)

        run.generation += 1
        view.frame.size.width = 360
        view.configure(.init(entry: compactWidgetEntry(run), bubbleMaxWidth: 360, typography: largeTypography()))
        view.layoutSubtreeIfNeeded()
        let collapse = try #require(reviewTeamDescendants(of: AppKitTranscriptHeaderToggleButton.self, in: view).first {
            $0.title == "Hide 1 not proposed"
        })
        #expect(!reviewTeamDescendants(of: AppKitReviewProposalVoteEvidenceView.self, in: view).isEmpty)
        #expect(!reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: view).isEmpty)
        let expandedHeight = view.intrinsicContentSize.height
        collapse.performClick(nil)
        view.layoutSubtreeIfNeeded()
        #expect(reviewTeamDescendants(of: AppKitReviewProposalVoteEvidenceView.self, in: view).isEmpty)
        #expect(view.intrinsicContentSize.height < expandedHeight)
    }

    private func largeTypography() -> TranscriptTypography {
        var settings = AppSettings()
        settings.chatFontSize = 24
        return TranscriptTypography(settings: settings)
    }

    private func compactWidgetEntry(_ run: ReviewTeamRun) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "collective-review-run:\(run.id)", toolName: "Collective review", content: .collectiveReviewRun(run),
            isComplete: !run.phase.isWorking, isError: run.phase == .failed
        )
    }
}
