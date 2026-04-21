import Foundation
import SwiftData

extension ContentView {
    func updateDiffViewer(item: SidebarItem?) {
        let target: DiffViewerSwitchTarget?

        switch item {
        case .thread(let thread):
            target = DiffViewerSwitchTarget.forThread(thread)
        case .project(let project):
            target = DiffViewerSwitchTarget.forProject(project)
        case .settings:
            target = diffViewerTargetForPreservedBookmark()
        default:
            target = nil
        }

        guard let target else {
            diffViewModel.clear()
            return
        }

        Task {
            await diffViewModel.switchToDirectory(
                target.path,
                baseRef: target.baseRef,
                remoteName: target.remoteName,
                conversationIds: target.conversationIds
            )
        }
    }

    func diffViewerTargetForPreservedBookmark() -> DiffViewerSwitchTarget? {
        switch appState.previousSelection {
        case .threadId(let id):
            guard let thread = uiModelContext.model(for: id) as? AgentThread,
                  thread.archivedAt == nil else {
                return nil
            }
            return DiffViewerSwitchTarget.forThread(thread)
        case .projectPath(let path):
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
            guard let project = try? uiModelContext.fetch(descriptor).first else {
                return nil
            }
            return DiffViewerSwitchTarget.forProject(project)
        default:
            return nil
        }
    }
}
