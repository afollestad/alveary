import Foundation
import SwiftData

@MainActor
extension AppComponent {
    var modelContainer: ModelContainer {
        shared {
            DataComponent.makeModelContainer(
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                persistentStoreURL: storageProfile.mainStoreURL
            )
        }
    }

    var modelContext: ModelContext {
        shared { ModelContext(modelContainer) }
    }

    var settingsService: SettingsService {
        shared { UserDefaultsSettingsService(defaults: storageProfile.settingsDefaults) }
    }

    var sessionManager: SessionManager {
        shared { DefaultSessionManager(supportDirectory: storageProfile.appSupportDirectory) }
    }

    var conversationAttachmentStore: any ConversationAttachmentStore {
        shared { DefaultConversationAttachmentStore(rootDirectory: storageProfile.conversationAttachmentsDirectory) }
    }

    var contextWindowCache: ContextWindowCache {
        shared { JSONContextWindowCache(fileURL: storageProfile.contextWindowCacheFileURL) }
    }
}
