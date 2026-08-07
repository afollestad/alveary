import XCTest

@testable import Alveary

@MainActor
final class GlobalInstructionsEditorModelTests: XCTestCase {
    func testLoadIfNeededSeedsDocumentAndClearsDirty() async {
        let service = StubInstructionsService(shared: "# Shared\n")
        let model = makeModel(service: service)

        await model.loadIfNeeded()

        XCTAssertEqual(model.draft.markdown, "# Shared")
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.linkStates["claude"], .linked)
    }

    func testLoadIfNeededIsIdempotentAndPreservesDraft() async {
        let service = StubInstructionsService(shared: "# Shared\n")
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        model.draft.replaceText("# Draft")
        model.noteDocumentChanged()

        service.shared = "# Changed on disk\n"
        await model.loadIfNeeded()

        XCTAssertEqual(model.draft.markdown, "# Draft")
        XCTAssertTrue(model.isDirty)
    }

    func testDiskReloadsBumpContentGenerationSoTheEditorHostInvalidates() async {
        let service = StubInstructionsService(shared: "# Shared\n")
        let model = makeModel(service: service)
        XCTAssertEqual(model.contentGeneration, 0)

        await model.loadIfNeeded()
        XCTAssertEqual(model.contentGeneration, 1)

        // Repeat loads keep the draft and must not churn the generation.
        await model.loadIfNeeded()
        XCTAssertEqual(model.contentGeneration, 1)

        await model.revert()
        XCTAssertEqual(model.contentGeneration, 2)

        // Saving writes the current document; the editor already shows it.
        await model.save()
        XCTAssertEqual(model.contentGeneration, 2)
    }

    func testNoteDocumentChangedSetsDirty() async {
        let model = makeModel(service: StubInstructionsService(shared: ""))
        await model.loadIfNeeded()

        model.noteDocumentChanged()

        XCTAssertTrue(model.isDirty)
    }

    func testSavePersistsDocumentMarkdownAndClearsDirty() async {
        let service = StubInstructionsService(shared: "")
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        model.draft.replaceText("# Draft")
        model.noteDocumentChanged()

        await model.save()

        XCTAssertEqual(service.shared, "# Draft")
        XCTAssertFalse(model.isDirty)
        XCTAssertNil(model.errorMessage)
    }

    func testSaveFailureSurfacesErrorWithoutClobberingDraft() async {
        let service = StubInstructionsService(shared: "")
        service.saveError = StubInstructionsError.diskFull
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        model.draft.replaceText("# Draft")
        model.noteDocumentChanged()

        await model.save()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.isDirty)
        XCTAssertEqual(model.draft.markdown, "# Draft")
    }

    func testRevertRestoresDiskContentAndClearsDirty() async {
        let service = StubInstructionsService(shared: "# Original\n")
        let model = makeModel(service: service)
        await model.loadIfNeeded()
        model.draft.replaceText("# Draft")
        model.noteDocumentChanged()

        await model.revert()

        XCTAssertEqual(model.draft.markdown, "# Original")
        XCTAssertFalse(model.isDirty)
    }

    func testLinkDelegatesThenReloadsSharedContentAndStates() async {
        let service = StubInstructionsService(shared: "# Shared\n")
        service.states = ["claude": .hasOwnFile(path: "/home/.claude/CLAUDE.md")]
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        service.onLink = { agentID, copyingContents in
            XCTAssertEqual(agentID, "claude")
            XCTAssertTrue(copyingContents)
            service.shared = "# Shared\n\n# Migrated\n"
            service.states = ["claude": .linked]
        }
        await model.link(agentID: "claude", copyingContents: true)

        XCTAssertTrue(model.draft.markdown.contains("# Migrated"))
        XCTAssertEqual(model.linkStates["claude"], .linked)
        XCTAssertFalse(model.isDirty)
    }

    func testCopyIntoSharedReloadsEditorContent() async {
        let service = StubInstructionsService(shared: "# Shared\n")
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        service.onCopyIntoShared = { _ in
            service.shared = "# Shared\n\n# Copied\n"
        }
        await model.copyIntoShared(agentID: "claude")

        XCTAssertTrue(model.draft.markdown.contains("# Copied"))
    }

    func testLinkRowsFollowRegistryOrderAndSkipMissingStates() async {
        let service = StubInstructionsService(shared: "")
        service.states = [
            "codex": .absent(path: "/home/.codex/AGENTS.md"),
            "claude": .linked
        ]
        let model = makeModel(service: service)
        await model.loadIfNeeded()

        XCTAssertEqual(model.linkRows.map(\.agent.id), ["claude", "codex"])
    }

    private func makeModel(service: StubInstructionsService) -> GlobalInstructionsEditorModel {
        GlobalInstructionsEditorModel(service: service, agentRegistry: DefaultAgentRegistry())
    }
}

// MARK: - Stubs

final class StubInstructionsService: GlobalAgentInstructionsService, @unchecked Sendable {
    var shared: String
    var states: [String: AgentInstructionsLinkState] = ["claude": .linked, "codex": .linked]
    var saveError: Error?
    var onLink: ((String, Bool) -> Void)?
    var onCopyIntoShared: ((String) -> Void)?

    init(shared: String) {
        self.shared = shared
    }

    var sharedPathDescription: String {
        "~/.agents/AGENTS.md"
    }

    func loadShared() async throws -> String {
        shared
    }

    func saveShared(_ markdown: String) async throws {
        if let saveError {
            throw saveError
        }
        shared = markdown
    }

    func linkStates() async -> [String: AgentInstructionsLinkState] {
        states
    }

    func copyIntoShared(agentID: String) async throws {
        onCopyIntoShared?(agentID)
    }

    func link(agentID: String, copyingContents: Bool) async throws {
        onLink?(agentID, copyingContents)
    }
}

enum StubInstructionsError: Error {
    case diskFull
}
