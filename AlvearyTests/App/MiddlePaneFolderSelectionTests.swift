import XCTest

@testable import Alveary

@MainActor
final class MiddlePaneFolderSelectionTests: XCTestCase {
    func testFolderChangesInvalidateTheMemoizedProjectDetails() {
        let makePane = makePaneFactory()
        let primary = WorkspaceFolderTarget(
            directory: "/tmp/app", source: SourceFolderSnapshot(path: "/tmp/app", baseRef: "main"), isPrimary: true
        )
        let secondary = WorkspaceFolderTarget(
            directory: "/tmp/library", source: SourceFolderSnapshot(path: "/tmp/library", baseRef: "develop"), isPrimary: false
        )
        let initialPane = makePane(primary)

        XCTAssertEqual(initialPane, makePane(primary))
        XCTAssertNotEqual(initialPane, makePane(secondary))
        XCTAssertNotEqual(initialPane, makePane(nil))
        XCTAssertEqual(makePane(nil), makePane(nil))
    }

    func testChangedFolderMetadataInvalidatesDetailsEvenWhenItsIdentityIsUnchanged() {
        let makePane = makePaneFactory()
        let source = SourceFolderSnapshot(path: "/tmp/app", remoteName: "origin", baseRef: "main")
        let original = WorkspaceFolderTarget(directory: source.path, source: source, isPrimary: true)
        var updatedSource = source
        updatedSource.remoteName = "upstream"
        updatedSource.baseRef = "develop"
        let updated = WorkspaceFolderTarget(directory: source.path, source: updatedSource, isPrimary: true)
        let relocated = WorkspaceFolderTarget(directory: "/tmp/moved-app", source: source, isPrimary: true)

        XCTAssertEqual(original.id, updated.id)
        XCTAssertNotEqual(makePane(original), makePane(updated))
        XCTAssertEqual(original.id, relocated.id)
        XCTAssertNotEqual(makePane(original), makePane(relocated))
    }

    private func makePaneFactory() -> @MainActor (WorkspaceFolderTarget?) -> MiddlePane {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)
        let dependencies = ContentViewDependencies.resolve(component)
        let appState = AppState()
        let bootstrap = ContentView.makeBootstrapState(dependencies: dependencies, appState: appState)
        let skillsViewModel = SkillsViewModel(skillsService: dependencies.skillsService)
        let mcpViewModel = MCPViewModel(mcpService: dependencies.mcpService)
        let scheduledTasksViewModel = ContentView.makeScheduledTasksViewModel(dependencies: dependencies)
        let settingsViewModel = ContentView.makeSettingsViewModel(dependencies: dependencies)

        return { selectedFolder in
            MiddlePane(
                appState: appState,
                selectedProjectFolder: selectedFolder,
                modelContext: dependencies.modelContainer.mainContext,
                gitHubCLI: dependencies.gitHubCLI,
                agentsManager: dependencies.agentsManager,
                conversationControllerRegistry: dependencies.conversationControllerRegistry,
                settingsService: dependencies.settingsService,
                providerRegistry: dependencies.providerRegistry,
                providerDiscovery: dependencies.providerDiscovery,
                providerSetup: dependencies.providerSetup,
                contextWindowCache: dependencies.contextWindowCache,
                fileListManager: dependencies.fileListManager,
                notificationManager: dependencies.notificationManager,
                voiceInputService: dependencies.voiceInputService,
                voiceInputLifecycleController: dependencies.voiceInputLifecycleController,
                sidebarViewModel: bootstrap.sidebarViewModel,
                loadInstalledSkills: { [] },
                diffViewModel: bootstrap.diffViewModel,
                diffViewerSwitchScope: { .toolbarStatsOnly },
                skillsViewModel: skillsViewModel,
                mcpViewModel: mcpViewModel,
                scheduledTasksViewModel: scheduledTasksViewModel,
                pullRequestsViewModel: bootstrap.pullRequestsViewModel,
                settingsViewModel: settingsViewModel,
                archivedThreadsViewModel: bootstrap.archivedThreadsViewModel,
                appUpdateManager: dependencies.appUpdateManager,
                targetSettingsPage: nil,
                onTargetSettingsPageHandled: { _ in }
            )
        }
    }
}
