/// View-facing names for the shared comparators. `SidebarOrderNormalization` owns the rules so
/// app-scoped lifecycle mutations sort identically.
extension SidebarViewModel {
    func compareRegularProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        SidebarOrderNormalization.compareRegularProjects(lhs, rhs)
    }

    func comparePinnedProjects(_ lhs: Project, _ rhs: Project) -> Bool {
        SidebarOrderNormalization.comparePinnedProjects(lhs, rhs)
    }

    func compareProjectFallback(_ lhs: Project, _ rhs: Project) -> Bool {
        SidebarOrderNormalization.compareProjectFallback(lhs, rhs)
    }

    func comparePinnedThreads(_ lhs: AgentThread, _ rhs: AgentThread) -> Bool {
        SidebarOrderNormalization.comparePinnedThreads(lhs, rhs)
    }
}
