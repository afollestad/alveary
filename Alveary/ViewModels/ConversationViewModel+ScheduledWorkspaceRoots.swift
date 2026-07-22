import Foundation

extension ConversationViewModel {
    func scheduledAdditionalWorkspaceRoots(in thread: AgentThread?) -> [String] {
        guard let thread else { return [] }
        return thread.mode == .task
            ? thread.taskWorkspaceDescriptor?.grantedRoots ?? []
            : thread.taskGrantedRoots
    }

    func mergedAllowedDirectories(configured: [String], additional: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for directory in configured + additional {
            let normalized = CanonicalPath.normalize(directory)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                continue
            }
            result.append(normalized)
        }
        return result
    }
}
