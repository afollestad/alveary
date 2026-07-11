import Foundation
import SwiftData

@testable import Alveary

@MainActor
final class AppShotCaptureControllerFixture {
    let container: ModelContainer
    let context: ModelContext
    let appState = AppState()
    let settingsService: InMemorySettingsService
    let runtimeStore = MockConversationRuntimeStore()
    let attachmentStore: AppShotRoutingAttachmentStore
    let prepareGate: AppShotRoutingPrepareGate
    let draftOpener: AppShotRoutingDraftOpener
    let feedback = AppShotRoutingFeedbackRecorder()
    let controller: AppShotCaptureController

    init(
        settings: AppSettings = AppSettings(),
        prepareError: AppShotCaptureError? = nil,
        pausesPreparation: Bool = false,
        storageError: AppShotRoutingTestError? = nil,
        pausesStorage: Bool = false,
        removalError: AppShotRoutingTestError? = nil,
        draftError: AppShotRoutingTestError? = nil,
        pausesDraftCreation: Bool = false,
        stagingError: AppShotRoutingTestError? = nil
    ) throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        settingsService = InMemorySettingsService(current: settings)
        attachmentStore = AppShotRoutingAttachmentStore(
            error: storageError,
            pausesStorage: pausesStorage,
            removalError: removalError
        )
        prepareGate = AppShotRoutingPrepareGate(
            error: prepareError,
            pausesPreparation: pausesPreparation
        )
        draftOpener = AppShotRoutingDraftOpener(
            context: context,
            error: draftError,
            pausesAfterCreation: pausesDraftCreation
        )

        let appState = appState
        let context = context
        let settingsService = settingsService
        let runtimeStore = runtimeStore
        let attachmentStore = attachmentStore
        let prepareGate = prepareGate
        let draftOpener = draftOpener
        let feedback = feedback
        controller = AppShotCaptureController(
            appState: appState,
            modelContext: context,
            settingsService: settingsService,
            runtimeStore: runtimeStore,
            attachmentStore: attachmentStore,
            prepareCapture: { try await prepareGate.prepare() },
            openDraft: { try await draftOpener.open(projectID: $0) },
            stageAppShot: { state, appShot in
                if let stagingError {
                    throw stagingError
                }
                state.stageAppShot(appShot)
            },
            presentPermission: feedback.recordPermission,
            activateAlveary: feedback.recordActivation,
            playSuccessSound: feedback.recordSuccessSound
        )
    }

    @discardableResult
    func insertProject(name: String, path: String) throws -> Project {
        let project = Project(path: path, name: name)
        context.insert(project)
        try context.save()
        return project
    }

    func insertThread(
        name: String,
        project: Project,
        isDraft: Bool = false,
        conversationIDs: [String] = ["main"]
    ) throws -> (thread: AgentThread, conversations: [Conversation]) {
        let thread = AgentThread(name: name, isDraft: isDraft, project: project)
        let conversations = conversationIDs.enumerated().map { index, id in
            Conversation(
                id: id,
                title: index == 0 ? "Main" : "Side \(index)",
                provider: "claude",
                isMain: index == 0,
                displayOrder: index,
                thread: thread
            )
        }
        thread.conversations = conversations
        project.threads.append(thread)
        context.insert(thread)
        conversations.forEach(context.insert)
        try context.save()
        return (thread, conversations)
    }

    func runCapture() async {
        let task = controller.captureIfIdle()
        await task?.value
    }
}

@MainActor
final class AppShotRoutingFeedbackRecorder {
    var activationCount = 0
    var successSoundCount = 0
    var permissions: [AppShotPermission] = []

    func recordPermission(_ permission: AppShotPermission) {
        permissions.append(permission)
    }

    func recordActivation() {
        activationCount += 1
    }

    func recordSuccessSound() {
        successSoundCount += 1
    }
}

actor AppShotRoutingPrepareGate {
    private let error: AppShotCaptureError?
    private let pausesPreparation: Bool
    private var preparationCount = 0
    private var didBeginPreparation = false
    private var preparationWaiters: [CheckedContinuation<Void, Never>] = []
    private var preparationContinuation: CheckedContinuation<Void, Never>?

    init(error: AppShotCaptureError?, pausesPreparation: Bool) {
        self.error = error
        self.pausesPreparation = pausesPreparation
    }

    func prepare() async throws -> PreparedAppShotCapture {
        preparationCount += 1
        didBeginPreparation = true
        preparationWaiters.forEach { $0.resume() }
        preparationWaiters.removeAll()
        if pausesPreparation, preparationCount == 1 {
            await withCheckedContinuation { preparationContinuation = $0 }
        }
        if let error {
            throw error
        }
        return PreparedAppShotCapture(
            appName: "Preview",
            bundleIdentifier: "com.apple.Preview",
            windowTitle: "Document",
            screenshotPNGData: Data("png".utf8),
            axTreeText: "standard window Document",
            focusedElementSummary: "button Open"
        )
    }

    func waitUntilPreparationBegins() async {
        guard !didBeginPreparation else {
            return
        }
        await withCheckedContinuation { preparationWaiters.append($0) }
    }

    func resumePreparation() {
        preparationContinuation?.resume()
        preparationContinuation = nil
    }

    func count() -> Int {
        preparationCount
    }
}

@MainActor
final class AppShotRoutingDraftOpener {
    private let context: ModelContext
    private let error: AppShotRoutingTestError?
    private let pausesAfterCreation: Bool
    private var didCreateDraft = false
    private var creationWaiters: [CheckedContinuation<Void, Never>] = []
    private var creationContinuation: CheckedContinuation<Void, Never>?
    private(set) var openCount = 0
    private(set) var lastProjectID: PersistentIdentifier?
    private(set) var createdThreadID: PersistentIdentifier?

    init(
        context: ModelContext,
        error: AppShotRoutingTestError?,
        pausesAfterCreation: Bool
    ) {
        self.context = context
        self.error = error
        self.pausesAfterCreation = pausesAfterCreation
    }

    func open(projectID: PersistentIdentifier) async throws -> PersistentIdentifier {
        openCount += 1
        lastProjectID = projectID
        if let error {
            throw error
        }
        guard let project = context.resolveProject(id: projectID) else {
            throw AppShotRoutingTestError.draftCreationFailed
        }
        let thread = AgentThread(name: "New thread", isDraft: true, project: project)
        let conversation = Conversation(id: "draft-\(UUID().uuidString)", provider: "claude", thread: thread)
        thread.conversations = [conversation]
        project.threads.append(thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        createdThreadID = thread.persistentModelID
        didCreateDraft = true
        creationWaiters.forEach { $0.resume() }
        creationWaiters.removeAll()
        if pausesAfterCreation {
            await withCheckedContinuation { creationContinuation = $0 }
        }
        return thread.persistentModelID
    }

    func waitUntilDraftIsCreated() async {
        guard !didCreateDraft else {
            return
        }
        await withCheckedContinuation { creationWaiters.append($0) }
    }

    func resumeDraftCreation() {
        creationContinuation?.resume()
        creationContinuation = nil
    }
}

actor AppShotRoutingAttachmentStore: ConversationAttachmentStore {
    nonisolated let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("alveary-app-shot-routing-\(UUID().uuidString)", isDirectory: true)
    private let error: AppShotRoutingTestError?
    private let pausesStorage: Bool
    private let removalError: AppShotRoutingTestError?
    private var didBeginStorage = false
    private var storageContinuation: CheckedContinuation<Void, Never>?
    private(set) var storedConversationIDs: [String] = []
    private(set) var removedAttachmentURLs: [URL] = []

    init(error: AppShotRoutingTestError?, pausesStorage: Bool, removalError: AppShotRoutingTestError?) {
        self.error = error
        self.pausesStorage = pausesStorage
        self.removalError = removalError
    }

    nonisolated func conversationRootDirectory(conversationId: String) -> URL {
        rootDirectory.appendingPathComponent(conversationId, isDirectory: true)
    }

    func copyLocalImages(_ urls: [URL], conversationId: String) async throws -> [LocalImageAttachment] {
        []
    }

    func storeAppShotScreenshot(_ data: Data, conversationId: String, label: String) async throws -> LocalImageAttachment {
        storedConversationIDs.append(conversationId)
        didBeginStorage = true
        if pausesStorage {
            await withCheckedContinuation { storageContinuation = $0 }
        }
        if let error {
            throw error
        }

        let directory = conversationRootDirectory(conversationId: conversationId)
            .appendingPathComponent("appshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture.png")
        try data.write(to: url, options: .atomic)
        return LocalImageAttachment(id: "capture", fileURL: url, label: label, createdAt: Date())
    }

    func cleanupUnreferenced(conversationId: String, keeping retainedURLs: Set<URL>, olderThan age: TimeInterval) async {}

    func removeAttachment(at url: URL) async throws {
        removedAttachmentURLs.append(url)
        if let removalError {
            throw removalError
        }
        try FileManager.default.removeItem(at: url)
    }

    func removeConversationDirectory(conversationId: String) async {
        try? FileManager.default.removeItem(at: conversationRootDirectory(conversationId: conversationId))
    }

    func hasBegunStorage() -> Bool {
        didBeginStorage
    }

    func resumeStorage() {
        storageContinuation?.resume()
        storageContinuation = nil
    }
}

enum AppShotRoutingTestError: LocalizedError, Equatable {
    case draftCreationFailed
    case removalFailed
    case stagingFailed
    case storageFailed

    var errorDescription: String? {
        switch self {
        case .draftCreationFailed:
            return "Draft creation failed."
        case .removalFailed:
            return "Removal failed."
        case .stagingFailed:
            return "Staging failed."
        case .storageFailed:
            return "Storage failed."
        }
    }
}
