import AgentCLIKit
import Foundation

/// Strict argument reading for the mutating thread tools.
///
/// Parsing is deliberately separate from validation: the canonical hash an exact retry is keyed on
/// has to be derivable from the request alone, before any host state is consulted, so a retry that
/// arrives after the world changed still replays its recorded result.
struct ThreadHostToolRequestParser {
    func parseCreate(arguments: [String: AgentCLIKit.JSONValue]) throws -> ThreadHostToolParsedCreateRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly([
            "mode",
            "project_path",
            "granted_roots",
            "name",
            "provider",
            "model",
            "effort",
            "permission_mode",
            "initial_prompt",
            "pinned",
            "section"
        ])
        let fields = ThreadHostToolCreateFields(
            mode: try object.optionalNonEmptyString("mode"),
            projectPath: try object.optionalNonEmptyString("project_path"),
            grantedRoots: try grantedRoots(in: object),
            name: try object.optionalNonEmptyString("name"),
            provider: try object.optionalNonEmptyString("provider"),
            model: try object.optionalNonEmptyString("model"),
            effort: try object.optionalNonEmptyString("effort"),
            permissionMode: try object.optionalNonEmptyString("permission_mode"),
            initialPrompt: try object.optionalNonEmptyString("initial_prompt"),
            pinned: try object.optionalBool("pinned"),
            section: try object.optionalNonEmptyString("section")
        )
        return ThreadHostToolParsedCreateRequest(
            workspace: try workspace(for: fields, in: object.path),
            name: fields.name,
            provider: fields.provider,
            model: fields.model,
            effort: fields.effort,
            permissionMode: fields.permissionMode,
            initialPrompt: fields.initialPrompt,
            pinned: fields.pinned,
            canonicalPayloadHash: try Self.canonicalPayloadHash(for: fields)
        )
    }

    func parseArchive(arguments: [String: AgentCLIKit.JSONValue]) throws -> String {
        try parseThreadIdentifier(arguments: arguments)
    }

    /// `create_section`. The name alone; whether one already exists is host state.
    func parseCreateSection(arguments: [String: AgentCLIKit.JSONValue]) throws -> String {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["name"])
        return try object.requiredNonEmptyString("name")
    }

    /// `move_thread_to_section`. Both required: this tool never guesses which thread or which
    /// section, unlike `unlink_pr`, whose omitted url has exactly one sensible resolution.
    func parseMoveThreadToSection(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> ThreadHostToolSectionMoveRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["thread_id", "section"])
        return ThreadHostToolSectionMoveRequest(
            threadID: try object.requiredNonEmptyString("thread_id"),
            sectionName: try object.requiredNonEmptyString("section")
        )
    }

    /// The shape every tool that names one thread and nothing else takes — archive, pin, unpin.
    func parseThreadIdentifier(arguments: [String: AgentCLIKit.JSONValue]) throws -> String {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["thread_id"])
        return try object.requiredNonEmptyString("thread_id")
    }

    /// `link_pr`. `thread_id` is optional: omitting it means the calling conversation's own thread.
    func parsePullRequestLink(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> ThreadHostToolPullRequestLinkRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "thread_id"])
        return ThreadHostToolPullRequestLinkRequest(
            identifier: try Self.identifier(from: object.requiredNonEmptyString("url")),
            threadID: try object.optionalNonEmptyString("thread_id")
        )
    }

    /// `unlink_pr`. Same shape as `link_pr` except `url` is optional, because a thread carrying one
    /// linked pull request leaves nothing for the caller to disambiguate; which one that is, is
    /// host state, so the handler resolves it.
    func parsePullRequestUnlink(
        arguments: [String: AgentCLIKit.JSONValue]
    ) throws -> ThreadHostToolPullRequestUnlinkRequest {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["url", "thread_id"])
        return ThreadHostToolPullRequestUnlinkRequest(
            identifier: try object.optionalNonEmptyString("url").map(Self.identifier(from:)),
            threadID: try object.optionalNonEmptyString("thread_id")
        )
    }

    /// The shape a read-only tool that names one thread and nothing else takes, where omitting it
    /// means the calling conversation's own thread.
    func parseOptionalThreadIdentifier(arguments: [String: AgentCLIKit.JSONValue]) throws -> String? {
        let object = StrictHostToolObject(arguments, path: "arguments")
        try object.requireOnly(["thread_id"])
        return try object.optionalNonEmptyString("thread_id")
    }

    private static func identifier(from url: String) throws -> PullRequestIdentifier {
        guard let identifier = PullRequestURLParser.identifier(from: url) else {
            throw ThreadHostToolServiceError.invalidPullRequestURL(url)
        }
        return identifier
    }
}

private struct ThreadHostToolCreateFields {
    let mode: String?
    let projectPath: String?
    let grantedRoots: [String]?
    let name: String?
    let provider: String?
    let model: String?
    let effort: String?
    let permissionMode: String?
    let initialPrompt: String?
    let pinned: Bool?
    let section: String?
}

private extension ThreadHostToolRequestParser {
    /// Resolves `mode`, `project_path`, and `granted_roots` into the placement they describe.
    ///
    /// A request naming neither inherits the calling thread's placement, which only the handler can
    /// resolve — where the caller works is host state. Grants ride along with that case rather than
    /// being refused here, because whether it lands on a Task is not knowable yet.
    func workspace(
        for fields: ThreadHostToolCreateFields,
        in path: String
    ) throws -> ThreadHostToolRequestedWorkspace {
        if let section = fields.section {
            guard fields.mode != "project" else {
                throw invalid("\(path).section applies only to a task thread; a project thread renders under its Project.")
            }
            guard fields.projectPath == nil else {
                throw invalid("\(path).section and \(path).project_path cannot both be set — a thread renders in one place.")
            }
            return .task(grantedRoots: fields.grantedRoots ?? [], sectionName: section)
        }
        switch fields.mode {
        case "project", nil:
            guard let projectPath = fields.projectPath else {
                guard fields.mode == nil else {
                    throw invalid("\(path).project_path is required for a project thread.")
                }
                return .inherit(grantedRoots: fields.grantedRoots ?? [])
            }
            guard fields.grantedRoots == nil else {
                throw invalid(
                    "\(path).granted_roots applies only to a task thread; a project thread already works inside " +
                        "its Project."
                )
            }
            return .project(path: projectPath)
        case "task":
            guard fields.projectPath == nil else {
                throw invalid(
                    "\(path).project_path does not apply to a task thread. A task thread works in its own private " +
                        "workspace; use granted_roots to give it access to a folder."
                )
            }
            return .task(grantedRoots: fields.grantedRoots ?? [])
        default:
            throw invalid("\(path).mode must be project or task.")
        }
    }

    /// Shape only. Whether a path is an absolute existing folder is host state, so it belongs to
    /// `ThreadHostToolService+Create.swift`.
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

    func invalid(_ message: String) -> HostToolRequestError {
        .invalidArguments(message)
    }

    /// Every field that changes what gets created, so a retry cannot replay a receipt for a
    /// differently configured thread. An omitted field and an explicitly defaulted one hash
    /// differently on purpose — the receipt records what was asked for, not what it resolved to.
    /// An inherited placement is safe to leave unhashed for the same reason its receipt is: the
    /// dedup key already scopes it to the source conversation the placement came from.
    static func canonicalPayloadHash(for fields: ThreadHostToolCreateFields) throws -> String {
        var object: [String: AgentCLIKit.JSONValue] = [
            "tool": .string(ThreadHostToolCatalog.createThreadToolName)
        ]
        if let grantedRoots = fields.grantedRoots {
            // Sorted: two requests granting the same folders are the same request whatever order
            // they were listed in.
            object["granted_roots"] = .array(grantedRoots.sorted().map(AgentCLIKit.JSONValue.string))
        }
        let optionalStrings: [String: String?] = [
            "mode": fields.mode,
            "project_path": fields.projectPath,
            "name": fields.name,
            "provider": fields.provider,
            "model": fields.model,
            "effort": fields.effort,
            "permission_mode": fields.permissionMode,
            "section": fields.section,
            "initial_prompt": fields.initialPrompt
        ]
        for (key, value) in optionalStrings {
            if let value {
                object[key] = .string(value)
            }
        }
        if let pinned = fields.pinned {
            object["pinned"] = .bool(pinned)
        }
        return HostToolDeduplication.sha256(try HostToolDeduplication.canonicalJSON(.object(object)))
    }
}
