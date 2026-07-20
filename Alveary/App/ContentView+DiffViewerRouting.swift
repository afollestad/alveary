import Foundation
import SwiftData

extension ContentView {
    func updateDiffViewer(item: SidebarItem?) {
        diffViewerSwitchGeneration &+= 1
        let generation = diffViewerSwitchGeneration

        let target: DiffViewerSwitchTarget?

        switch item {
        case .thread(let selectedThread):
            guard let thread = uiModelContext.resolveThread(id: selectedThread.persistentModelID) else {
                target = nil
                break
            }
            if thread.effectiveMode == .project, thread.isDraft, let project = thread.project {
                target = resolvedDiffViewerTarget(for: project)
            } else {
                target = resolvedDiffViewerTarget(for: thread)
            }
        case .project(let selectedProject):
            guard let project = uiModelContext.resolveProject(id: selectedProject.persistentModelID) else {
                target = nil
                break
            }
            target = resolvedDiffViewerTarget(for: project)
        case .settings:
            target = diffViewerTargetForPreservedBookmark()
        default:
            target = nil
        }

        guard let target else {
            diffViewModel.clear()
            return
        }

        // The toolbar diff summary must stay fresh even while the pane is
        // hidden; only the heavy pane payload waits for the pane to show.
        let scope: DiffViewerSwitchScope = isDiffViewerRendered ? .full : .toolbarStatsOnly

        Task {
            guard generation == diffViewerSwitchGeneration else {
                return
            }
            await diffViewModel.switchToTarget(target, scope: scope)
        }
    }

    func diffViewerTargetForPreservedBookmark() -> DiffViewerSwitchTarget? {
        switch appState.previousSelection {
        case .threadId(let id):
            guard let thread = uiModelContext.resolveThread(id: id),
                  thread.archivedAt == nil else {
                return nil
            }
            if thread.effectiveMode == .project, thread.isDraft, let project = thread.project {
                return resolvedDiffViewerTarget(for: project)
            }
            return DiffViewerSwitchTarget.forThread(
                thread,
                candidateConversationIDs: liveDiffViewerConversationIDs(for: thread)
            )
        case .projectPath(let path):
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
            guard let project = try? uiModelContext.fetch(descriptor).first else {
                return nil
            }
            return resolvedDiffViewerTarget(for: project)
        default:
            return nil
        }
    }

    private func resolvedDiffViewerTarget(for thread: AgentThread) -> DiffViewerSwitchTarget? {
        guard let liveThread = uiModelContext.resolveThread(id: thread.persistentModelID),
              liveThread.archivedAt == nil else {
            return nil
        }
        return DiffViewerSwitchTarget.forThread(
            liveThread,
            candidateConversationIDs: liveDiffViewerConversationIDs(for: liveThread)
        )
    }

    private func resolvedDiffViewerTarget(for project: Project) -> DiffViewerSwitchTarget {
        let threads = liveDiffViewerThreads(for: project)
        return DiffViewerSwitchTarget.forProject(
            project,
            candidateThreads: threads,
            candidateConversationIDs: liveDiffViewerConversationIDs(for: project, threads: threads)
        )
    }

    private func liveDiffViewerThreads(for project: Project) -> [AgentThread] {
        let projectPath = project.path
        let descriptor = FetchDescriptor<AgentThread>(
            predicate: #Predicate { thread in
                thread.archivedAt == nil && thread.isDraft == false && thread.project?.path == projectPath
            }
        )
        return ((try? uiModelContext.fetch(descriptor)) ?? []).filter { $0.effectiveMode == .project }
    }

    private func liveDiffViewerConversationIDs(for thread: AgentThread) -> Set<String> {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        return Set(((try? uiModelContext.fetch(descriptor)) ?? []).map(\.id))
    }

    private func liveDiffViewerConversationIDs(for project: Project, threads: [AgentThread]) -> Set<String> {
        let qualifyingThreads = threads.filter { $0.worktreePath == nil || $0.worktreePath == project.path }
        return Set(qualifyingThreads.flatMap { liveDiffViewerConversationIDs(for: $0) })
    }
}
