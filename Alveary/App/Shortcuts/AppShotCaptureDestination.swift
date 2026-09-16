import Foundation
import SwiftData

struct AppShotDestinationIntent {
    enum Route {
        case conversation(AppShotConversationSnapshot)
        case draft(PersistentIdentifier?)
    }

    let navigationToken: AppShotNavigationToken
    let route: Route

    @MainActor
    static func resolve(
        appState: AppState,
        modelContext: ModelContext,
        settingsService: any SettingsService
    ) throws -> AppShotDestinationIntent {
        let navigationToken = AppShotNavigationToken(appState: appState)
        if case .thread(let selectedThread) = appState.selectedSidebarItem {
            guard let thread = modelContext.resolveThread(id: selectedThread.persistentModelID),
                  thread.archivedAt == nil else {
                throw AppShotRoutingError.destinationUnavailable
            }
            let conversation: Conversation?
            if thread.isDraft {
                let threadID = thread.persistentModelID
                let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { candidate in
                    candidate.thread?.persistentModelID == threadID && candidate.isMain
                })
                conversation = try? modelContext.fetch(descriptor).first
            } else {
                conversation = selectedConversation(in: thread, modelContext: modelContext, appState: appState)
            }
            guard let conversation else {
                throw AppShotRoutingError.destinationUnavailable
            }
            return AppShotDestinationIntent(
                navigationToken: navigationToken,
                route: .conversation(AppShotConversationSnapshot(thread: thread, conversation: conversation))
            )
        }

        let resolution = NewThreadProjectResolver.resolve(
            selection: appState.selectedSidebarItem,
            previousSelection: appState.previousSelection,
            lastActiveProjectID: settingsService.current.lastActiveProjectID,
            legacyProjectPath: settingsService.current.lastActiveProjectPath,
            modelContext: modelContext
        )
        settingsService.updateLastActiveProjectID(resolution.lastActiveProjectID)
        return AppShotDestinationIntent(
            navigationToken: navigationToken,
            route: .draft(resolution.project?.persistentModelID)
        )
    }

    @MainActor
    func isCurrent(
        appState: AppState,
        modelContext: ModelContext,
        settingsService: any SettingsService
    ) -> Bool {
        guard navigationToken == AppShotNavigationToken(appState: appState) else {
            return false
        }

        switch route {
        case .conversation(let snapshot):
            guard let thread = modelContext.resolveThread(id: snapshot.threadID),
                  thread.archivedAt == nil,
                  let conversation = modelContext.resolveConversation(id: snapshot.conversationPersistentID),
                  conversation.thread?.persistentModelID == snapshot.threadID else {
                return false
            }
            if thread.isDraft {
                return conversation.isMain && thread.project?.persistentModelID == snapshot.draftProjectID
            }
            return selectedConversation(in: thread, modelContext: modelContext, appState: appState)?.persistentModelID ==
                snapshot.conversationPersistentID
        case .draft(let projectID):
            let resolution = NewThreadProjectResolver.resolve(
                selection: appState.selectedSidebarItem,
                previousSelection: appState.previousSelection,
                lastActiveProjectID: settingsService.current.lastActiveProjectID,
                legacyProjectPath: settingsService.current.lastActiveProjectPath,
                modelContext: modelContext
            )
            return resolution.project?.persistentModelID == projectID
        }
    }
}

struct AppShotConversationSnapshot {
    let threadID: PersistentIdentifier
    let conversationPersistentID: PersistentIdentifier
    let conversationID: String
    let draftProjectID: PersistentIdentifier?
    let destinationName: String

    @MainActor
    init(thread: AgentThread, conversation: Conversation) {
        threadID = thread.persistentModelID
        conversationPersistentID = conversation.persistentModelID
        conversationID = conversation.id
        draftProjectID = thread.isDraft ? thread.project?.persistentModelID : nil
        if thread.isDraft, let projectName = thread.project?.name {
            destinationName = "the new thread in \(projectName)"
        } else {
            destinationName = thread.displayName()
        }
    }

    func claim(opensDraftOnSuccess: Bool) -> AppShotDestinationClaim {
        AppShotDestinationClaim(
            threadID: threadID,
            conversationPersistentID: conversationPersistentID,
            conversationID: conversationID,
            destinationName: destinationName,
            opensDraftOnSuccess: opensDraftOnSuccess
        )
    }
}

struct AppShotDestinationClaim {
    let threadID: PersistentIdentifier
    let conversationPersistentID: PersistentIdentifier
    let conversationID: String
    let destinationName: String
    let opensDraftOnSuccess: Bool
}

enum AppShotNavigationToken: Equatable {
    case none
    case skills
    case mcp
    case scheduled
    case pullRequests
    case archived
    case project(PersistentIdentifier)
    // Effective conversation selection is checked in `isCurrent`; the raw selection cache may be repaired without changing destinations.
    case thread(PersistentIdentifier)
    case settings(previousSelection: AppState.SidebarBookmark?)

    @MainActor
    init(appState: AppState) {
        switch appState.selectedSidebarItem {
        case .skills:
            self = .skills
        case .mcp:
            self = .mcp
        case .scheduled:
            self = .scheduled
        case .pullRequests:
            self = .pullRequests
        case .archived:
            self = .archived
        case .project(let project):
            self = .project(project.persistentModelID)
        case .thread(let thread):
            self = .thread(thread.persistentModelID)
        case .settings:
            self = .settings(previousSelection: appState.previousSelection)
        case nil:
            self = .none
        }
    }
}

enum AppShotRoutingError: LocalizedError, Equatable {
    case destinationUnavailable
    case draftUnavailable
    case destinationDeleted

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            return "Could not resolve a conversation for the app shot."
        case .draftUnavailable:
            return "Could not create a new thread for the app shot."
        case .destinationDeleted:
            return "The app-shot destination was deleted before the capture finished."
        }
    }
}

struct AppShotAttachmentCleanupError: LocalizedError, Equatable {
    let originalError: String
    let cleanupError: String

    var errorDescription: String? {
        "\(originalError) Removing the stored app-shot screenshot also failed: \(cleanupError)"
    }
}
