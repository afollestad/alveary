import Foundation

extension ConversationViewModel {
    func ensureAppShotProviderPrerequisites(appShots: [AppShotAttachment]) async throws {
        guard !appShots.isEmpty else {
            return
        }
        let providerID = conversation.provider ?? settingsService.current.defaultProvider
        guard AppShotProviderStrategy(providerID: providerID) != nil else {
            throw AppShotCaptureError.unsupportedProvider(providerID)
        }
        guard providerID == "claude" else {
            return
        }
        guard !needsSetup else {
            return
        }
        try await ensureClaudeAppShotDirectoryGrant(appShots: appShots)
    }

    func claudeAppShotDirectoriesIfNeeded(appShots: [AppShotAttachment]) -> [String] {
        let providerID = conversation.provider ?? settingsService.current.defaultProvider
        guard providerID == "claude" else {
            return []
        }
        return appShotAttachmentStoreRoots(appShots: appShots)
    }

    func hasClaudeAppShotDirectoryGrant(for appShots: [AppShotAttachment]) -> Bool {
        let required = Set(appShotAttachmentStoreRoots(appShots: appShots))
        guard !required.isEmpty else {
            return true
        }
        let granted = Set((state.liveSessionConfig?.allowedDirectories ?? []).map(CanonicalPath.normalize))
        return required.isSubset(of: granted)
    }

    func appShotDebugPreview(providerID: String, userInput: String) throws -> String {
        guard let strategy = AppShotProviderStrategy(providerID: providerID) else {
            throw AppShotCaptureError.unsupportedProvider(providerID)
        }
        return AppShotTransportFormatter.debugPreview(
            userInput: userInput,
            appShots: state.stagedAppShots,
            strategy: strategy
        )
    }
}

private extension ConversationViewModel {
    func ensureClaudeAppShotDirectoryGrant(appShots: [AppShotAttachment]) async throws {
        let required = appShotAttachmentStoreRoots(appShots: appShots)
        guard !required.isEmpty, !hasClaudeAppShotDirectoryGrant(for: appShots) else {
            return
        }
        guard !isAgentActivelyWorking else {
            throw AgentError.spawnFailed("Claude app shots need the screenshot directory grant before steering")
        }

        let config = try makeSpawnConfig(
            allowedDirectories: required,
            settingsSource: .currentContinuation
        )
        let result = try await reconfigureSession(config: config)
        guard result != .nextTurnRequired else {
            throw AgentError.spawnFailed("Claude app shots will send on the next turn after the screenshot directory grant is applied")
        }
    }

    func appShotAttachmentStoreRoots(appShots: [AppShotAttachment]) -> [String] {
        var roots: [String] = []
        var seen = Set<String>()
        for appShot in appShots {
            let path = CanonicalPath.normalize(appShot.attachmentStoreRoot.path)
            guard !path.isEmpty, seen.insert(path).inserted else {
                continue
            }
            roots.append(path)
        }
        return roots
    }
}
