import SwiftData

extension ThreadDetailView {
    func projectTrustTaskID(for conversation: Conversation) -> String {
        guard let context = projectTrustContext(for: conversation) else {
            return "none"
        }

        return [
            String(describing: context.threadID),
            context.providerID,
            context.canonicalProjectPath,
            String(thread.hasCompletedInitialSetup)
        ].joined(separator: "|")
    }

    @MainActor
    func refreshProjectTrustPrompt(for conversation: Conversation) async {
        guard let context = projectTrustContext(for: conversation) else {
            projectTrustPrompt = nil
            isCheckingProjectTrust = false
            return
        }

        isCheckingProjectTrust = true
        let isTrusted = await providerSetup.isTrustedProject(
            providerId: context.providerID,
            workingDirectory: context.canonicalProjectPath
        )
        guard isVisibleThreadContext(context) else {
            isCheckingProjectTrust = false
            return
        }

        if isTrusted {
            projectTrustPrompt = nil
            isCheckingProjectTrust = false
            return
        }

        if settingsService.current.autoTrustProjects {
            await providerSetup.trustProject(
                providerId: context.providerID,
                workingDirectory: context.canonicalProjectPath
            )
            let isTrustedAfterWrite = await providerSetup.isTrustedProject(
                providerId: context.providerID,
                workingDirectory: context.canonicalProjectPath
            )
            guard isVisibleThreadContext(context) else {
                isCheckingProjectTrust = false
                return
            }

            if isTrustedAfterWrite {
                projectTrustPrompt = nil
            } else {
                projectTrustPrompt = context
            }
            isCheckingProjectTrust = false
            return
        }

        projectTrustPrompt = context
        isCheckingProjectTrust = false
    }

    @MainActor
    func trustProject(_ prompt: ProjectTrustPrompt) async {
        guard isVisibleThreadContext(prompt) else {
            return
        }

        isCheckingProjectTrust = true
        await providerSetup.trustProject(
            providerId: prompt.providerID,
            workingDirectory: prompt.canonicalProjectPath
        )
        guard isVisibleThreadContext(prompt) else {
            isCheckingProjectTrust = false
            return
        }

        let isTrusted = await providerSetup.isTrustedProject(
            providerId: prompt.providerID,
            workingDirectory: prompt.canonicalProjectPath
        )
        guard isVisibleThreadContext(prompt) else {
            isCheckingProjectTrust = false
            return
        }

        if isTrusted {
            projectTrustPrompt = nil
        } else {
            projectTrustPrompt = prompt
        }
        isCheckingProjectTrust = false
    }

    @MainActor
    func denyProjectTrust(_ prompt: ProjectTrustPrompt) {
        guard isVisibleThreadContext(prompt),
              case .thread(let selectedThread) = appState.selectedSidebarItem,
              selectedThread.persistentModelID == prompt.threadID,
              let dbThread = uiModelContext.resolveThread(id: prompt.threadID),
              !dbThread.hasCompletedInitialSetup else {
            return
        }

        let replacementItem = dbThread.project.map(SidebarItem.project)
        let conversationIDs = dbThread.conversations.map(\.id)
        notificationManager.forgetConversations(withIDs: conversationIDs)
        appState.selectedConversationIDs.removeValue(forKey: prompt.threadID)
        appState.selectedSidebarItem = replacementItem
        projectTrustPrompt = nil
        isCheckingProjectTrust = false

        uiModelContext.delete(dbThread)

        do {
            try uiModelContext.save()
        } catch {
            conversationActionError = "Couldn't delete untrusted thread: \(error.localizedDescription)"
        }
    }

    @MainActor
    func observeProjectTrustUpdates(for conversation: Conversation) async {
        guard projectTrustContext(for: conversation) != nil else {
            return
        }

        let updates = await providerSetup.projectTrustUpdates()
        for await _ in updates {
            guard !Task.isCancelled else {
                return
            }
            await refreshProjectTrustPrompt(for: conversation)
        }
    }

    func projectTrustContext(for conversation: Conversation) -> ProjectTrustPrompt? {
        guard let thread = conversation.thread,
              !thread.hasCompletedInitialSetup,
              let project = thread.project else {
            return nil
        }

        let providerID = conversation.provider ?? settingsService.current.defaultProvider

        return ProjectTrustPrompt(
            threadID: thread.persistentModelID,
            canonicalProjectPath: CanonicalPath.normalize(project.path),
            projectName: project.name,
            providerID: providerID
        )
    }

    func isVisibleThreadContext(_ prompt: ProjectTrustPrompt) -> Bool {
        guard thread.persistentModelID == prompt.threadID,
              case .thread(let selectedThread) = appState.selectedSidebarItem,
              selectedThread.persistentModelID == prompt.threadID else {
            return false
        }

        return true
    }

    func cachedProjectTrustStatus(for prompt: ProjectTrustPrompt) -> Bool? {
        providerSetup.cachedProjectTrustStatus(
            providerId: prompt.providerID,
            workingDirectory: prompt.canonicalProjectPath
        )
    }

    func visibleProjectTrustPrompt(for prompt: ProjectTrustPrompt, cachedStatus: Bool?) -> ProjectTrustPrompt? {
        if projectTrustPrompt == prompt {
            return prompt
        }
        guard settingsService.current.autoTrustProjects == false,
              cachedStatus == false else {
            return nil
        }

        return prompt
    }
}
