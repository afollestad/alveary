import Foundation
import SwiftData

/// Persist exact app-issued inputs before launch; a resumed run never reconstructs history from newer prompt templates.
extension PullRequestReviewTeamCoordinator {
    // swiftlint:disable:next function_parameter_count
    func beginAttempt(
        run: ReviewTeamRun, member: ReviewWorkerConfiguration, phase: ReviewTeamRun.Phase,
        packet: ReviewPacketLease, prompt: String, executionID: String
    ) async throws {
        guard let historyStore else { return }
        do {
            let current = try requireActive(run.conversationID, generation: run.generation)
            guard (current.history?.count ?? 0) < ReviewTeamAttempt.maximumCount else {
                throw ReviewTeamHistoryCaptureError.attemptLimit
            }
            let inputData = try await Task.detached {
                try packet.validate()
                let files = try packet.fileNames.map { name in
                    (name, try Data(contentsOf: packet.directoryURL.appendingPathComponent(name)))
                }
                try packet.validate()
                return files
            }.value
            _ = try requireActive(run.conversationID, generation: run.generation)
            let promptArtifact = try await historyStore.save(
                conversationID: run.conversationID, runID: run.id, name: "prompt.txt", data: Data(prompt.utf8)
            )
            _ = try requireActive(run.conversationID, generation: run.generation)
            var inputs: [ReviewHistoryArtifact] = []
            for (name, data) in inputData {
                inputs.append(try await historyStore.save(conversationID: run.conversationID, runID: run.id, name: name, data: data))
                _ = try requireActive(run.conversationID, generation: run.generation)
            }
            guard (try requireActive(run.conversationID, generation: run.generation).history?.count ?? 0)
                < ReviewTeamAttempt.maximumCount else { throw ReviewTeamHistoryCaptureError.attemptLimit }
            try update(run.conversationID, generation: run.generation) { current in
                if current.history == nil { current.historyIsPartial = true }
                current.history = (current.history ?? []) + [ReviewTeamAttempt(
                    id: executionID, reviewerID: member.id, phase: phase, generation: run.generation,
                    startedAt: .now, packetHash: packet.inputHash, prompt: promptArtifact, inputs: inputs, status: .running
                )]
            }
        } catch {
            throw historyCaptureError(error)
        }
    }

    // swiftlint:disable:next function_parameter_count
    func executeAttempt<T: Sendable>(
        run: ReviewTeamRun, member: ReviewWorkerConfiguration, packet: ReviewPacketLease,
        prompt: String, executionID: String, validate: @Sendable (String) throws -> T
    ) async throws -> Result<T, ReviewTeamError> {
        let text: String
        do {
            text = try await worker.execute(
                configuration: member, packet: packet, prompt: prompt,
                runID: run.id, generation: run.generation, executionID: executionID
            )
        } catch {
            try await finishAttempt(run: run, executionID: executionID,
                                    status: error is CancellationError ? .cancelled : .failed, error: error)
            throw error
        }
        _ = try requireActive(run.conversationID, generation: run.generation)
        let result: Result<T, ReviewTeamError>
        do {
            result = .success(try validate(text))
        } catch let error as ReviewTeamError {
            result = .failure(error)
        } catch {
            try await finishAttempt(run: run, executionID: executionID, status: .failed, response: text, error: error)
            throw error
        }
        switch result {
        case .success:
            try await finishAttempt(run: run, executionID: executionID, status: .succeeded, response: text)
        case .failure(let error):
            try await finishAttempt(run: run, executionID: executionID, status: .invalid, response: text, error: error)
        }
        return result
    }

    func finishAttempt(
        run: ReviewTeamRun, executionID: String, status: ReviewTeamAttempt.Status,
        response: String? = nil, error: Error? = nil
    ) async throws {
        guard let historyStore else { return }
        do {
            _ = try requireActive(run.conversationID, generation: run.generation)
            var responseArtifact: ReviewHistoryArtifact?
            if let response {
                responseArtifact = try await historyStore.save(
                    conversationID: run.conversationID, runID: run.id, name: "response.txt", data: Data(response.utf8)
                )
                _ = try requireActive(run.conversationID, generation: run.generation)
            }
            try update(run.conversationID, generation: run.generation) { current in
                guard let index = current.history?.firstIndex(where: { $0.id == executionID && $0.status == .running }),
                      let attempt = current.history?[index] else { return }
                if status == .invalid {
                    // Persist the retry budget with the response so a crash cannot grant another correction.
                    current.attempts["\(attempt.phase.rawValue):\(attempt.reviewerID)", default: 0] += 1
                }
                current.history?[index].status = status
                current.history?[index].finishedAt = .now
                current.history?[index].error = error.map(ReviewTeamDiagnostics.persisted)
                current.history?[index].response = responseArtifact
            }
        } catch {
            throw historyCaptureError(error)
        }
    }

    func pruneHistory() {
        guard let historyStore,
              let conversations = try? modelContext.fetch(FetchDescriptor<Conversation>()) else { return }
        let retainedIDs = Set(conversations.map(\.id))
        Task { try? await historyStore.prune(retainingConversationIDs: retainedIDs) }
    }

    func conversationDidDelete(_ conversationID: String) {
        let runID = runs[conversationID]?.id
        cancel(conversationID: conversationID)
        forgetRun(conversationID: conversationID)
        if let runID { try? cancellationStore.remove(runID: runID) }
        Task { [worker, historyStore] in
            if let runID { await worker.cancel(runID: runID) }
            try? await historyStore?.remove(conversationID: conversationID)
        }
    }

    private func historyCaptureError(_ error: Error) -> Error {
        if error is CancellationError || error is ReviewTeamHistoryCaptureError { return error }
        if let error = error as? ReviewTeamError, error == .cancelled || error == .missingConversation { return error }
        return ReviewTeamHistoryCaptureError.unavailable(ReviewTeamDiagnostics.persisted(error))
    }
}
