import XCTest

@testable import Alveary

@MainActor
extension HostToolTranscriptCatalogTests {
    func testDescriptorLookupCoversEveryThreadMutationTool() {
        for hostToolName in [
            ThreadHostToolCatalog.createThreadToolName,
            ThreadHostToolCatalog.pinThreadToolName,
            ThreadHostToolCatalog.unpinThreadToolName,
            ThreadHostToolCatalog.archiveThreadToolName
        ] {
            XCTAssertNotNil(HostToolTranscriptCatalog.descriptor(forToolName: hostToolName), hostToolName)
            // Claude qualifies host tool names; Codex reports them bare. Both must match.
            XCTAssertNotNil(
                HostToolTranscriptCatalog.descriptor(
                    forToolName: HostToolTranscriptCatalog.toolName(hostToolName)
                ),
                hostToolName
            )
        }
        // The lookups change nothing, so they stay ordinary tool rows.
        for hostToolName in [
            ThreadHostToolCatalog.listThreadsToolName,
            ThreadHostToolCatalog.listProjectsToolName
        ] {
            XCTAssertNil(HostToolTranscriptCatalog.descriptor(forToolName: hostToolName), hostToolName)
        }
    }

    /// Every thread mutation applies immediately, so its result is the whole outcome; there is
    /// no marker to correlate and nothing to resolve later.
    func testThreadActionWidgetsCarryNoOutcomeKey() {
        let descriptor = HostToolTranscriptCatalog.descriptor(
            forToolName: ThreadHostToolCatalog.pinThreadToolName
        )
        XCTAssertNil(descriptor?.outcomeKey(Self.pinnedOutput))
    }

    func testCreateContentReadsAsRunningBeforeItsResultArrives() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .create,
                input: #"{"name":"Add caching"}"#,
                output: nil,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .running)
        XCTAssertNil(content.threadID)

        let entry = entry(content, action: .create)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Creating thread…")
        XCTAssertNil(entry.openableTarget)
    }

    func testCreatedResultNamesTheThreadAndOpensIt() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .create,
                input: #"{"project_path":"/repos/alveary"}"#,
                output: """
                {"status":"created","thread_id":"conv-1","name":"Add caching","workspace_kind":"project",\
                "project_path":"/repos/alveary","message":"Created the thread \\"Add caching\\" in /repos/alveary."}
                """,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)

        let entry = entry(content, action: .create)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Thread created: Add caching")
        // Only a Project thread has a path; a Task thread's card carries no detail line.
        XCTAssertEqual(HostToolWidgetSummary.detail(for: entry), "/repos/alveary")
        XCTAssertEqual(entry.openableTarget, .thread("conv-1"))
        XCTAssertTrue(entry.isSettledWithoutDecision)
        XCTAssertNil(entry.openablePullRequest)
    }

    func testPinnedResultUsesItsOwnCopy() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .pin,
                input: Self.threadInput,
                output: Self.pinnedOutput,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)

        let entry = entry(content, action: .pin)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Thread pinned: Add caching")
        XCTAssertNil(HostToolWidgetSummary.detail(for: entry))
        XCTAssertEqual(entry.openableTarget, .thread("conv-1"))
    }

    /// `already_pinned` is a success the sidebar already reflects, so it must not read as a
    /// failure — and the card still opens the thread it names.
    func testAlreadyPinnedResultSaysSoAndStillOpens() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .pin,
                input: Self.threadInput,
                output: Self.threadOutput(status: "already_pinned"),
                isError: false
            )
        )
        XCTAssertEqual(content.status, .unchanged)

        let entry = entry(content, action: .pin)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Thread already pinned: Add caching")
        XCTAssertEqual(entry.openableTarget, .thread("conv-1"))
    }

    func testUnpinCopyCoversBothOutcomes() throws {
        let unpinned = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .unpin,
                input: Self.threadInput,
                output: Self.threadOutput(status: "unpinned"),
                isError: false
            )
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry(unpinned, action: .unpin)),
            "Thread unpinned: Add caching"
        )

        let unchanged = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .unpin,
                input: Self.threadInput,
                output: Self.threadOutput(status: "already_unpinned"),
                isError: false
            )
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry(unchanged, action: .unpin)),
            "Thread was not pinned: Add caching"
        )
    }

    func testArchiveCopyCoversBothOutcomes() throws {
        let archived = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .archive,
                input: Self.threadInput,
                output: Self.threadOutput(status: "archived"),
                isError: false
            )
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry(archived, action: .archive)),
            "Thread archived: Add caching"
        )
        // The thread is gone from the sidebar, but the card still routes to where it now lives.
        XCTAssertEqual(entry(archived, action: .archive).openableTarget, .thread("conv-1"))

        let unchanged = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .archive,
                input: Self.threadInput,
                output: Self.threadOutput(status: "already_archived"),
                isError: false
            )
        )
        XCTAssertEqual(
            HostToolWidgetSummary.text(for: entry(unchanged, action: .archive)),
            "Thread was already archived: Add caching"
        )
    }

    /// A refusal has no thread to describe, so the reason takes the detail line.
    func testFailedPinReportsTheReasonAndCannotBeOpened() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .pin,
                input: Self.threadInput,
                output: "The thread sits under a pinned project, which already carries it.",
                isError: true
            )
        )
        XCTAssertEqual(content.status, .failed)

        let entry = HostToolWidgetEntry(
            id: "tool-1",
            toolName: ThreadHostToolCatalog.pinThreadToolName,
            content: .threadAction(content),
            isComplete: true,
            isError: true
        )
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Could not pin the thread")
        XCTAssertEqual(
            HostToolWidgetSummary.detail(for: entry),
            "The thread sits under a pinned project, which already carries it."
        )
        XCTAssertNil(entry.openableTarget)
    }

    /// Codex surfaces the plain-text fallback rather than structured content. `create_thread`
    /// is the one action whose request cannot name its thread, so its message is the only
    /// source for both the name and the id the card opens.
    func testPlainTextCreateRecoversItsThreadFromTheMessage() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .create,
                input: "{}",
                output: """
                Created the thread "Add caching" in /repos/alveary (id: conv-9) using claude, \
                model opus, effort medium, permissions on-request.
                """,
                isError: false
            )
        )
        XCTAssertEqual(content.status, .applied)
        XCTAssertEqual(content.name, "Add caching")
        XCTAssertEqual(content.threadID, "conv-9")
        XCTAssertNil(content.projectPath)

        let entry = entry(content, action: .create)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry), "Thread created: Add caching")
        XCTAssertEqual(entry.openableTarget, .thread("conv-9"))
    }

    /// The other actions require `thread_id`, so a text-fallback card still opens the right
    /// thread even though the result parsed as nothing.
    func testPlainTextPinFallsBackToTheRequestedThread() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .pin,
                input: Self.threadInput,
                output: "Pinned the thread \"Add caching\" to the top of Alveary's sidebar.",
                isError: false
            )
        )
        XCTAssertEqual(content.threadID, "conv-1")
        XCTAssertEqual(content.name, "Add caching")
    }

    /// A structured receipt's fields are the answer; parsing its message could only invent a
    /// thread id from copy that quotes one.
    func testStructuredReceiptNeverParsesItsMessage() throws {
        let content = try XCTUnwrap(
            ThreadActionWidgetParsing.content(
                action: .create,
                input: "{}",
                output: #"{"status":"created","message":"Created the thread \"Ghost\" (id: conv-9)."}"#,
                isError: false
            )
        )
        XCTAssertNil(content.threadID)
        XCTAssertNil(content.name)
        XCTAssertEqual(HostToolWidgetSummary.text(for: entry(content, action: .create)), "Thread created")
    }

    func testUnreadableThreadRequestFallsBackToTheGenericToolRow() {
        XCTAssertNil(
            ThreadActionWidgetParsing.content(action: .pin, input: "not json", output: nil, isError: false)
        )
        XCTAssertNil(
            ThreadActionWidgetParsing.content(action: .pin, input: nil, output: nil, isError: false)
        )
    }

    private func entry(
        _ content: ThreadActionWidgetContent,
        action: ThreadActionWidgetContent.Action
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-1",
            toolName: Self.toolName(for: action),
            content: .threadAction(content),
            isComplete: content.status != .running
        )
    }

    private static func toolName(for action: ThreadActionWidgetContent.Action) -> String {
        switch action {
        case .create:
            ThreadHostToolCatalog.createThreadToolName
        case .pin:
            ThreadHostToolCatalog.pinThreadToolName
        case .unpin:
            ThreadHostToolCatalog.unpinThreadToolName
        case .archive:
            ThreadHostToolCatalog.archiveThreadToolName
        }
    }

    static let threadInput = #"{"thread_id":"conv-1"}"#

    static var pinnedOutput: String {
        threadOutput(status: "pinned")
    }

    static func threadOutput(status: String) -> String {
        """
        {"status":"\(status)","thread_id":"conv-1","name":"Add caching","is_pinned":true,\
        "message":"The thread \\"Add caching\\" is pinned."}
        """
    }
}
