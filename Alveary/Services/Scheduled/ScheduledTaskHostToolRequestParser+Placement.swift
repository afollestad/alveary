import AgentCLIKit
import Foundation

/// Parsing and canonicalization for the optional destination/workspace fields.
///
/// Everything here is structural: shape, key allowlists, and mutual exclusions. Whether a
/// Project is registered, a thread is an eligible target, or a grant was already the caller's
/// belongs to `ScheduledTaskHostToolService+ProposalResolution.swift`, which can see host state.
extension ScheduledTaskHostToolRequestParser {
    static let placementKeys: Set<String> = ["destination", "target_thread_id", "workspace"]

    func parsePlacement(in object: StrictHostToolObject) throws -> ScheduledTaskProposalPlacement? {
        let destination = try object.optionalNonEmptyString("destination")
        let targetThreadID = try object.optionalNonEmptyString("target_thread_id")
        let workspaceValues = try object.optionalObject("workspace")

        switch destination {
        case "existing_thread":
            guard workspaceValues == nil else {
                throw invalid("\(object.path).workspace does not apply to an existing-thread destination.")
            }
            guard let targetThreadID else {
                throw invalid("\(object.path).target_thread_id is required for an existing-thread destination.")
            }
            return .existingThread(targetConversationID: targetThreadID)
        case "new_thread":
            guard targetThreadID == nil else {
                throw invalid("\(object.path).target_thread_id only applies to an existing-thread destination.")
            }
            return .newThread(workspace: try workspaceValues.map { try parseWorkspace($0, in: object.path) })
        case .some:
            throw invalid("\(object.path).destination must be new_thread or existing_thread.")
        case nil:
            guard targetThreadID == nil else {
                throw invalid("\(object.path).target_thread_id requires destination existing_thread.")
            }
            // A workspace only means anything for a new-thread run, so naming one says which
            // destination is meant; an edit that names a workspace is asking to switch to it.
            guard let workspaceValues else {
                return nil
            }
            return .newThread(workspace: try parseWorkspace(workspaceValues, in: object.path))
        }
    }
}

private extension ScheduledTaskHostToolRequestParser {
    /// `parentPath` keeps an edit's errors pointing at `arguments.changes.workspace`, so the
    /// model is told which object to fix.
    func parseWorkspace(
        _ values: [String: AgentCLIKit.JSONValue],
        in parentPath: String
    ) throws -> ScheduledTaskProposalWorkspace {
        let object = StrictHostToolObject(values, path: "\(parentPath).workspace")
        try object.requireOnly(["kind", "project_path", "granted_roots"])
        let kind = try object.requiredNonEmptyString("kind")
        let projectPath = try object.optionalNonEmptyString("project_path")
        let grantedRoots = try grantedRoots(in: object)

        switch kind {
        case "project":
            guard let projectPath else {
                throw invalid("\(object.path).project_path is required for a project workspace.")
            }
            return .project(path: projectPath, grantedRoots: grantedRoots)
        case "private":
            guard projectPath == nil else {
                throw invalid("\(object.path).project_path does not apply to a private workspace.")
            }
            return .privateWorkspace(grantedRoots: grantedRoots)
        default:
            throw invalid("\(object.path).kind must be project or private.")
        }
    }

    func grantedRoots(in object: StrictHostToolObject) throws -> [String]? {
        guard let values = try object.optionalArray("granted_roots") else {
            return nil
        }
        let roots = try values.enumerated().map { index, value in
            guard case .string(let path) = value else {
                throw invalid("\(object.path).granted_roots[\(index)] must be a string.")
            }
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw invalid("\(object.path).granted_roots[\(index)] must not be empty.")
            }
            return trimmed
        }
        guard Set(roots).count == roots.count else {
            throw invalid("\(object.path).granted_roots must not contain duplicate paths.")
        }
        return roots
    }
}

extension ScheduledTaskHostToolRequestParser {
    /// Canonical form for the retry-deduplication hash. Two requests that differ only in where
    /// the task would run must not collapse into one replayed receipt.
    func canonicalValue(for placement: ScheduledTaskProposalPlacement) -> AgentCLIKit.JSONValue {
        switch placement {
        case .existingThread(let targetConversationID):
            return .object([
                "destination": .string("existing_thread"),
                "target_thread_id": .string(targetConversationID)
            ])
        case .newThread(let workspace):
            var object: [String: AgentCLIKit.JSONValue] = ["destination": .string("new_thread")]
            guard let workspace else {
                return .object(object)
            }
            var workspaceValues: [String: AgentCLIKit.JSONValue] = [
                "kind": .string(workspace.kind.rawValue)
            ]
            if let projectPath = workspace.projectPath {
                workspaceValues["project_path"] = .string(projectPath)
            }
            if let grantedRoots = workspace.grantedRoots {
                workspaceValues["granted_roots"] = .array(grantedRoots.sorted().map(AgentCLIKit.JSONValue.string))
            }
            object["workspace"] = .object(workspaceValues)
            return .object(object)
        }
    }
}
