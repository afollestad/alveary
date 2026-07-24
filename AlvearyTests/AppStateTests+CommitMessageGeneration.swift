import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension AppStateTests {
    func testCompletesMatchingCommitMessageGenerationRequestExactlyOnce() throws {
        let fixture = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        )
        let state = AppState()
        var completions: [Result<String, Error>] = []

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: fixture.primaryConversations[0].persistentModelID,
            completion: { completions.append($0) }
        )
        let requestID = try XCTUnwrap(state.pendingCommitMessageGenerationRequest?.id)

        state.completeCommitMessageGenerationRequest(id: requestID, result: .success("Commit"))
        state.completeCommitMessageGenerationRequest(id: requestID, result: .success("Duplicate"))
        state.cancelPendingCommitMessageGenerationRequest()

        XCTAssertNil(state.pendingCommitMessageGenerationRequest)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(try completions[0].get(), "Commit")
    }

    func testReplacingCommitMessageGenerationRequestFailsThePreviousOne() throws {
        let fixture = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        )
        let state = AppState()
        var capturedError: Error?

        state.requestCommitMessageGeneration(
            prompt: "First",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: fixture.primaryConversations[0].persistentModelID,
            completion: { result in
                if case .failure(let error) = result {
                    capturedError = error
                }
            }
        )
        state.requestCommitMessageGeneration(
            prompt: "Second",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: fixture.primaryConversations[0].persistentModelID,
            completion: { _ in }
        )

        XCTAssertEqual(state.pendingCommitMessageGenerationRequest?.prompt, "Second")
        XCTAssertEqual(
            capturedError?.localizedDescription,
            CommitMessageGenerationError.activeConversationChanged.localizedDescription
        )
    }

    func testCommitMessageGenerationSurvivesSelectionValidationForItsOwnConversation() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true)
        let fixture = try makeFixture(primaryConversations: [mainConversation])
        let state = AppState()
        state.selectedSidebarItem = .thread(fixture.primaryThread)

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: mainConversation.persistentModelID,
            completion: { _ in }
        )

        state.invalidateCommitMessageGenerationForSelectionChange()

        XCTAssertNotNil(state.pendingCommitMessageGenerationRequest)
    }

    func testCommitMessageGenerationIsCancelledWhenSelectedThreadChanges() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true)
        let fixture = try makeFixture(primaryConversations: [mainConversation])
        let state = AppState()
        state.selectedSidebarItem = .thread(fixture.primaryThread)
        var capturedError: Error?

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: mainConversation.persistentModelID,
            completion: { result in
                if case .failure(let error) = result {
                    capturedError = error
                }
            }
        )

        state.selectedSidebarItem = .project(try XCTUnwrap(fixture.primaryThread.project))
        state.invalidateCommitMessageGenerationForSelectionChange()

        XCTAssertNil(state.pendingCommitMessageGenerationRequest)
        XCTAssertEqual(
            capturedError?.localizedDescription,
            CommitMessageGenerationError.activeConversationChanged.localizedDescription
        )
    }

    func testCancelsCommitMessageGenerationRequestWhenSelectedConversationChanges() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true)
        let sideConversation = Conversation(title: "Side", provider: "claude", isMain: false, displayOrder: 2)
        let fixture = try makeFixture(primaryConversations: [mainConversation, sideConversation])
        let state = AppState()
        var capturedError: Error?

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: mainConversation.persistentModelID,
            completion: { result in
                if case .failure(let error) = result {
                    capturedError = error
                }
            }
        )

        state.selectConversation(sideConversation, in: fixture.primaryThread)

        XCTAssertNil(state.pendingCommitMessageGenerationRequest)
        XCTAssertEqual(
            capturedError?.localizedDescription,
            CommitMessageGenerationError.activeConversationChanged.localizedDescription
        )
    }

    func testCancellationSwallowsALateSuccessOrErrorFromAStaleConversationTask() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true)
        let fixture = try makeFixture(primaryConversations: [mainConversation])
        let state = AppState()
        var completions: [Result<String, Error>] = []

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: mainConversation.persistentModelID,
            completion: { completions.append($0) }
        )
        let requestID = try XCTUnwrap(state.pendingCommitMessageGenerationRequest?.id)

        state.cancelPendingCommitMessageGenerationRequest()
        state.completeCommitMessageGenerationRequest(id: requestID, result: .success("Late"))
        state.completeCommitMessageGenerationRequest(
            id: requestID,
            result: .failure(CommitMessageGenerationError.interrupted)
        )

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(
            completionErrorDescription(try XCTUnwrap(completions.first)),
            CommitMessageGenerationError.activeConversationChanged.localizedDescription
        )
    }

    func testSameThreadConversationChangeCancelsTheRequest() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true)
        let sideConversation = Conversation(title: "Side", provider: "claude", isMain: false, displayOrder: 2)
        let fixture = try makeFixture(primaryConversations: [mainConversation, sideConversation])
        let state = AppState()
        state.selectedSidebarItem = .thread(fixture.primaryThread)

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            threadID: fixture.primaryThread.persistentModelID,
            conversationID: mainConversation.persistentModelID,
            completion: { _ in }
        )

        // The request stores its explicit conversation, so the map entry is authoritative.
        XCTAssertEqual(
            state.selectedConversationIDs[fixture.primaryThread.persistentModelID],
            mainConversation.persistentModelID
        )

        state.selectedConversationIDs[fixture.primaryThread.persistentModelID] = sideConversation.persistentModelID
        state.invalidateCommitMessageGenerationForSelectionChange()

        XCTAssertNil(state.pendingCommitMessageGenerationRequest)
    }

    private func completionErrorDescription(_ result: Result<String, Error>) -> String? {
        guard case .failure(let error) = result else {
            return nil
        }
        return error.localizedDescription
    }
}
