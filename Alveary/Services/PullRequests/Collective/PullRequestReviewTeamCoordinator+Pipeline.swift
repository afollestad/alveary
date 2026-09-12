import Foundation

extension PullRequestReviewTeamCoordinator {
    struct PreparedInput: Sendable {
        let detail: PullRequestDetail
        let files: [DiffFile]
        let packetFiles: [String: Data]
        let lease: ReviewPacketLease
    }

    func perform(conversationID: String, generation: Int) async throws {
        let original = try requireActive(conversationID, generation: generation)
        for configuration in original.team { try await worker.preflight(configuration) }
        let input = try await prepareInput(original)
        var run = try applyPreparedInput(input, to: original)
        if run.retryPhase != .crossChecking, run.continuedPhases?.contains(.inspecting) != true {
            try await inspect(run, input: input)
        }
        run = try requireActive(conversationID, generation: generation)
        guard run.inspections.count >= run.requiredVotes else { throw ReviewTeamError.quorumRequired(run.requiredVotes) }
        if try pauseForPartialCompletion(run, phase: .inspecting) { return }
        let candidates = run.team.flatMap { run.inspections[$0.id]?.findings ?? [] }.sorted { $0.id < $1.id }
        if !candidates.isEmpty {
            try await consolidate(run, candidates: candidates, input: input)
            try await verifyRevision(run)
            run = try requireActive(conversationID, generation: generation)
            if run.continuedPhases?.contains(.crossChecking) != true { try await crossCheck(run, input: input) }
            run = try requireActive(conversationID, generation: generation)
            guard run.voteReports.count >= run.requiredVotes else { throw ReviewTeamError.quorumRequired(run.requiredVotes) }
            if try pauseForPartialCompletion(run, phase: .crossChecking) { return }
            let accepted = try ReviewTeamConsensus.accepted(
                findings: run.canonical?.findings ?? [], reports: run.voteReports, team: run.team
            )
            try update(conversationID, generation: generation) { $0.accepted = accepted }
        }
        try update(conversationID, generation: generation) { $0.phase = .staging }
        try await stageResult(try requireActive(conversationID, generation: generation), input: input)
    }

    func prepareInput(_ run: ReviewTeamRun) async throws -> PreparedInput {
        let detail = try await service.fetchDetail(run.identifier)
        guard detail.status == .open || detail.status == .draft, detail.viewerLogin != nil,
              let base = detail.baseRefOid, let head = detail.headRefOid, !base.isEmpty, !head.isEmpty else {
            throw ReviewTeamError.invalidOutput("The pull request is not reviewable or its revision is unavailable.")
        }
        if let previous = run.headOID, previous != head || run.baseOID != base { throw ReviewTeamError.revisionChanged }
        let snapshot = try await service.fetchDiffSnapshot(run.identifier)
        guard snapshot.baseOID == base, snapshot.headOID == head else { throw ReviewTeamError.revisionChanged }
        guard snapshot.files.count == detail.changedFiles else {
            throw ReviewTeamError.invalidOutput("The complete pull request diff could not be loaded.")
        }
        let feedback = try await service.fetchReviewFeedback(run.identifier)
        let (diff, files) = try await Task.detached {
            guard snapshot.byteCount <= 64 * 1024 * 1024 else { throw PullRequestsServiceError.responseTooLarge }
            let data = try Data(contentsOf: snapshot.url)
            guard data.count == snapshot.byteCount, let text = String(data: data, encoding: .utf8) else {
                throw PullRequestDiffError.invalidEncoding
            }
            // Parse the same bytes workers receive, rather than rereading a potentially changed file through its old index.
            let files = DiffParser.parse(text)
            guard files.count == snapshot.files.count,
                  files.map(\.path) == snapshot.files.map({ $0.metadata.path }) else {
                throw PullRequestDiffError.invalidEncoding
            }
            return (data, files)
        }.value
        _ = try requireActive(run.conversationID, generation: run.generation)
        let prior = try priorRecord(run)
        let context = ["url": run.url.absoluteString, "title": detail.title, "description": detail.bodyMarkdown,
                       "baseOID": base, "headOID": head]
        let priorInput = PriorPacket(
            event: prior?.event, body: prior?.body,
            comments: (prior?.stagedComments ?? []).map { PriorPacket.Comment(path: $0.path, line: $0.line, side: $0.side, body: $0.body) }
        )
        let packetFiles = [
            "context.json": try ReviewTeamDigest.encode(context), "changes.diff": diff,
            "published-feedback.json": feedback, "prior-proposal.json": try ReviewTeamDigest.encode(priorInput)
        ]
        let lease = try await packets.create(runID: run.id, files: packetFiles)
        return PreparedInput(detail: detail, files: files, packetFiles: packetFiles, lease: lease)
    }

    func verifyRevision(_ run: ReviewTeamRun) async throws {
        let detail = try await service.fetchDetail(run.identifier)
        _ = try requireActive(run.conversationID, generation: run.generation)
        guard detail.headRefOid == run.headOID, detail.baseRefOid == run.baseOID else { throw ReviewTeamError.revisionChanged }
    }

    private func applyPreparedInput(_ input: PreparedInput, to original: ReviewTeamRun) throws -> ReviewTeamRun {
        var run = try requireActive(original.conversationID, generation: original.generation)
        if run.retryPhase != nil || run.continuedPhases?.isEmpty == false {
            guard run.inputHash == input.lease.inputHash else { throw ReviewTeamError.retryInputChanged }
        }
        if let oldHash = run.inputHash, oldHash != input.lease.inputHash {
            run.inspections = [:]
            run.canonical = nil
            run.voteReports = [:]
            run.attempts = [:]
            run.failures = [:]
            run.continuedPhases = nil
        }
        run.inputHash = input.lease.inputHash
        run.baseOID = input.detail.baseRefOid
        run.headOID = input.detail.headRefOid
        run.accepted = []
        run.resultHash = nil
        run.supersededProposalIDs = []
        run.phase = run.retryPhase == .crossChecking ? .crossChecking : .inspecting
        try persist(run)
        return run
    }

    private func inspect(_ run: ReviewTeamRun, input: PreparedInput) async throws {
        try await withThrowingTaskGroup(of: (String, Result<ReviewInspectionReport, Error>).self) { group in
            for member in run.team where run.inspections[member.id] == nil {
                group.addTask { [self] in
                    do {
                        let report = try await executeStep(run: run, member: member, phase: .inspecting, packet: input.lease,
                                                           prompt: ReviewTeamPrompts.inspect(criteria: run.criteria)) {
                            try ReviewTeamConsensus.inspection($0, files: input.files)
                        }
                        return (member.id, .success(report))
                    } catch { return (member.id, .failure(error)) }
                }
            }
            for try await (member, outcome) in group {
                if case .failure(let error) = outcome, error is ReviewTeamHistoryCaptureError { throw error }
                try update(run.conversationID, generation: run.generation) { current in
                    switch outcome {
                    case .success(let report):
                        if current.inspections[member] != report {
                            current.canonical = nil
                            current.voteReports = [:]
                            current.accepted = []
                            current.continuedPhases = current.continuedPhases?.filter { $0 != .crossChecking }
                            current.attempts = current.attempts.filter { $0.key.hasPrefix("inspecting:") }
                            current.failures = current.failures.filter { $0.key.hasPrefix("inspecting:") }
                        }
                        current.inspections[member] = report
                        current.failures.removeValue(forKey: "inspecting:\(member)")
                    case .failure(let error):
                        current.failures["inspecting:\(member)"] = ReviewTeamDiagnostics.persisted(error)
                    }
                }
            }
        }
    }

    private func consolidate(_ run: ReviewTeamRun, candidates: [ReviewCandidate], input: PreparedInput) async throws {
        guard run.canonical == nil, let lead = run.team.first else { return }
        try update(run.conversationID, generation: run.generation) { $0.phase = .consolidating }
        var files = input.packetFiles
        files["candidates.json"] = try ReviewTeamDigest.encode(candidates)
        let packet = try await packets.create(runID: run.id, files: files)
        let report = try await executeStep(run: run, member: lead, phase: .consolidating, packet: packet,
                                           prompt: ReviewTeamPrompts.consolidate(criteria: run.criteria)) {
            try ReviewTeamConsensus.canonical($0, candidates: candidates)
        }
        try update(run.conversationID, generation: run.generation) { $0.canonical = report; $0.voteReports = [:] }
    }

    private func crossCheck(_ run: ReviewTeamRun, input: PreparedInput) async throws {
        guard let canonical = run.canonical else { throw ReviewTeamError.invalidOutput("Missing canonical findings.") }
        try update(run.conversationID, generation: run.generation) { $0.phase = .crossChecking }
        var files = input.packetFiles
        files["canonical.json"] = try ReviewTeamDigest.encode(canonical)
        let packet = try await packets.create(runID: run.id, files: files)
        try await withThrowingTaskGroup(of: (String, Result<ReviewVoteReport, Error>).self) { group in
            for member in run.team where run.voteReports[member.id] == nil {
                group.addTask { [self] in
                    do {
                        let report = try await executeStep(run: run, member: member, phase: .crossChecking, packet: packet,
                                                           prompt: ReviewTeamPrompts.crossCheck(criteria: run.criteria)) {
                            try ReviewTeamConsensus.votes($0, reviewerID: member.id, findings: canonical.findings)
                        }
                        return (member.id, .success(report))
                    } catch { return (member.id, .failure(error)) }
                }
            }
            for try await (member, outcome) in group {
                if case .failure(let error) = outcome, error is ReviewTeamHistoryCaptureError { throw error }
                try update(run.conversationID, generation: run.generation) { current in
                    switch outcome {
                    case .success(let report):
                        current.voteReports[member] = report
                        current.failures.removeValue(forKey: "crossChecking:\(member)")
                    case .failure(let error):
                        current.failures["crossChecking:\(member)"] = ReviewTeamDiagnostics.persisted(error)
                    }
                }
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func executeStep<T: Sendable>(
        run: ReviewTeamRun, member: ReviewWorkerConfiguration, phase: ReviewTeamRun.Phase,
        packet: ReviewPacketLease, prompt: String, validate: @Sendable (String) throws -> T
    ) async throws -> T {
        let key = "\(phase.rawValue):\(member.id)"
        let priorInvalidResponses = try requireActive(
            run.conversationID,
            generation: run.generation
        ).attempts[key, default: 0]
        var correction = priorInvalidResponses == 0
            ? ""
            : "\nYour previous response was invalid. Return corrected JSON only."
        var invalidResponses = priorInvalidResponses
        while invalidResponses < 2 {
            let executionID = UUID().uuidString
            let composedPrompt = prompt + correction
            try await beginAttempt(
                run: run, member: member, phase: phase, packet: packet, prompt: composedPrompt, executionID: executionID
            )
            switch try await executeAttempt(
                run: run, member: member, packet: packet, prompt: composedPrompt, executionID: executionID, validate: validate
            ) {
            case .success(let report):
                return report
            case .failure(let error):
                invalidResponses += 1
                try update(run.conversationID, generation: run.generation) {
                    $0.attempts[key] = invalidResponses
                }
                correction = "\nYour previous response was invalid: \(error.localizedDescription) Return corrected JSON only."
            }
        }
        throw ReviewTeamError.invalidOutput("The reviewer did not return a valid response after one corrective retry.")
    }
}

private struct PriorPacket: Encodable {
    struct Comment: Encodable {
        let path: String
        let line: Int
        let side: String
        let body: String
    }
    let event: String?
    let body: String?
    let comments: [Comment]
}
