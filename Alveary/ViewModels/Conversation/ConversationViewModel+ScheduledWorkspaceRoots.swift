import Foundation

extension ConversationViewModel {
    func effectiveAdditionalWorkspaceRoots(in thread: AgentThread?, workingDirectory: String) throws -> [String] {
        guard let snapshot = thread?.workspaceSnapshot else { throw WorkspaceFolderError.invalidSnapshot }
        return snapshot.additionalWorkspaceRoots(workingDirectory: workingDirectory)
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
