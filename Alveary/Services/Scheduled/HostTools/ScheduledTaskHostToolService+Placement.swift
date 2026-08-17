import Foundation

/// Resolves a requested destination and workspace against trusted host state.
///
/// The parser has already checked shape; everything here answers questions only Alveary can:
/// is that thread a real target, is that Project registered, and was that folder already the
/// caller's to give away.
extension ScheduledTaskHostToolService {
    struct ResolvedTargetThread {
        let thread: AgentThread
        let conversationID: String
    }

    struct ResolvedWorkspace {
        let kind: ScheduledTaskWorkspaceKind
        let project: Project?
        let grantedRoots: [String]
    }

    /// Resolves a `target_thread_id` from `list_threads` into a thread a schedule may post into.
    func resolveTargetThread(conversationID: String) throws -> ResolvedTargetThread {
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
              conversation.isMain,
              let thread = conversation.thread else {
            throw ScheduledTaskHostToolServiceError.targetThreadNotFound
        }
        guard thread.isEligibleScheduledTaskTarget,
              let mainConversation = thread.soleMainConversation else {
            throw ScheduledTaskHostToolServiceError.targetThreadIneligible
        }
        return ResolvedTargetThread(thread: thread, conversationID: mainConversation.id)
    }

    /// Applies a requested workspace over the one the task would otherwise inherit.
    ///
    /// A `nil` request inherits outright. A Project must already be registered — an unknown path
    /// is refused rather than registered on the fly. `granted_roots` replaces the inherited set
    /// and may add folders the conversation could not already reach, matching what the editor
    /// pane allows; every grant is disclosed in the placement summary and the confirmation pane.
    func resolvedWorkspace(
        requested: ScheduledTaskProposalWorkspace?,
        inheritedKind: ScheduledTaskWorkspaceKind,
        inheritedProject: Project?,
        inheritedGrantedRoots: [String]
    ) throws -> ResolvedWorkspace {
        guard let requested else {
            return ResolvedWorkspace(
                kind: inheritedKind,
                project: inheritedProject,
                grantedRoots: inheritedGrantedRoots
            )
        }

        let project: Project?
        switch requested {
        case .project(let path, _):
            project = try resolveRegisteredProject(path: path)
        case .privateWorkspace:
            project = nil
        }

        return ResolvedWorkspace(
            kind: requested.kind,
            project: project,
            grantedRoots: try resolvedGrantedRoots(
                requested: requested.grantedRoots,
                inherited: inheritedGrantedRoots
            )
        )
    }

    func existingThreadDraft(
        title: String,
        prompt: String,
        recurrence: ScheduledTaskRecurrence,
        targetConversationID: String,
        settings: ScheduledTaskProposalAgentSettings
    ) -> ScheduledTaskProposalDefinitionDraft {
        // An existing-thread run adopts its target's workspace, which is why the mutation
        // service clears the Project and forces a private workspace for this destination.
        ScheduledTaskProposalDefinitionDraft(
            title: title,
            prompt: prompt,
            destination: .existingThread,
            targetConversationID: targetConversationID,
            recurrence: recurrence,
            timeZoneIdentifier: currentTimeZone().identifier,
            providerID: settings.providerID,
            model: settings.model,
            effort: settings.effort,
            permissionMode: settings.permissionMode,
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: [],
            projectPath: nil
        )
    }
}

extension ScheduledTaskHostToolService {
    /// One sentence naming what the request asked for, or `nil` when it inherited everything.
    ///
    /// This is the disclosure a plain-text provider can relay: a create that pins a thread or
    /// reaches into another Project should be describable before the user opens the pane.
    static func placementSummary(
        for placement: ScheduledTaskProposalPlacement?,
        targetThread: AgentThread?,
        project: Project?,
        grantedRoots: [String]
    ) -> String? {
        switch placement {
        case .existingThread:
            guard let targetThread else {
                return nil
            }
            let pinNote = targetThread.isPinned ? "" : ", which will be pinned when you confirm"
            return "It will post into the existing thread \"\(targetThread.displayName())\"\(pinNote)."
        case let .newThread(flavor, workspace):
            let sentences = flavorSentences(flavor) + workspaceSentences(
                workspace,
                project: project,
                grantedRoots: grantedRoots
            )
            return sentences.isEmpty ? nil : sentences.joined(separator: " ")
        case nil:
            return nil
        }
    }

    private static func flavorSentences(_ flavor: ScheduledTaskNewThreadFlavor?) -> [String] {
        switch flavor {
        case .reused:
            ["It will create a thread on its first run and reuse it afterward."]
        case .perRun:
            ["It will create a fresh thread on every run."]
        case nil:
            []
        }
    }

    private static func workspaceSentences(
        _ workspace: ScheduledTaskProposalWorkspace?,
        project: Project?,
        grantedRoots: [String]
    ) -> [String] {
        guard let workspace else {
            return []
        }
        var sentences: [String] = []
        if let project {
            sentences.append("It will run in the \"\(project.name)\" Project.")
        } else if case .privateWorkspace = workspace {
            sentences.append("It will run in a private workspace.")
        }
        if workspace.grantedRoots != nil {
            sentences.append(grantedRoots.isEmpty
                ? "It will have no folder grants."
                : "It will have these folder grants: \(grantedRoots.joined(separator: ", ")).")
        }
        return sentences
    }
}

private extension ScheduledTaskHostToolService {
    func resolveRegisteredProject(path: String) throws -> Project {
        let candidates = [path, CanonicalPath.normalize(path)]
        guard let project = candidates.lazy.compactMap({ self.modelContext.resolveProject(path: $0) }).first else {
            throw ScheduledTaskHostToolServiceError.projectNotRegistered(path: path)
        }
        try ScheduledTaskHostToolSupport.validateStoredCanonicalPath(project.path)
        return project
    }

    /// A selected root that is already inherited keeps its inherited literal. A new root must be
    /// an absolute path to an existing folder and is stored canonically resolved — the same shape
    /// the editor's folder picker produces — so a symlink spelling cannot show the user one
    /// folder in the pane while granting another at run time.
    func resolvedGrantedRoots(requested: [String]?, inherited: [String]) throws -> [String] {
        guard let requested else {
            return inherited
        }
        let resolved = try requested.map { path -> String in
            if let match = inherited.first(where: { $0 == path }) {
                return match
            }
            guard path.hasPrefix("/") else {
                throw ScheduledTaskHostToolServiceError.grantRootUnavailable(path: path)
            }
            let normalized = CanonicalPath.normalize(path)
            if let match = inherited.first(where: { $0 == normalized }) {
                return match
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ScheduledTaskHostToolServiceError.grantRootUnavailable(path: path)
            }
            return normalized
        }
        return ScheduledTask.normalizedUniquePaths(resolved)
    }
}
