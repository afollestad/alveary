import Foundation

extension ChatItemGrouper {
    static func toolSummary(name: String?, input: String?) -> String {
        if let skillSummary = skillToolSummary(name: name, input: input) {
            return skillSummary
        }

        guard let name else {
            return "Tool"
        }
        guard let json = parsedJSONDictionary(from: input) else {
            return name
        }

        return toolSummary(name: name, json: json)
    }

    private static func toolSummary(name: String, json: [String: Any]) -> String {
        switch name {
        case "Read":
            return readToolSummary(from: json)
        case "Edit", "Write":
            return fileMutationToolSummary(name: name, json: json)
        case "FileChange":
            return CodexFileChangePresentation.parse(from: json)?.rowSummary(isComplete: false) ?? name
        case let name where CommandToolPresentation.isCommandToolName(name):
            return commandToolSummary(name: name, json: json)
        case "Grep", "Glob":
            return "Searching for pattern `\(json["pattern"] as? String ?? "")`"
        case "ToolSearch":
            return toolSearchSummary(from: json)
        case "Agent":
            return json["description"] as? String ?? json["subagent_type"] as? String ?? "Sub-agent"
        case "TodoWrite":
            return todoWriteSummary(from: json)
        default:
            return name
        }
    }

    func parseTodoWriteInput(_ input: String?) -> [TaskEntry] {
        guard let json = Self.parsedJSONDictionary(from: input),
              let todos = json["todos"] as? [[String: Any]] else {
            return []
        }

        return todos.enumerated().compactMap { index, todo in
            guard let content = todo["content"] as? String else {
                return nil
            }

            let status = TaskEntry.Status(taskListRawValue: todo["status"] as? String ?? "pending")
            return TaskEntry(
                id: "task-\(index)",
                content: content,
                activeForm: todo["activeForm"] as? String,
                status: status
            )
        }
    }

    func parseAgentToolInput(_ input: String?) -> (agentType: String, description: String) {
        guard let json = Self.parsedJSONDictionary(from: input) else {
            return ("general-purpose", "")
        }

        return (
            json["subagent_type"] as? String ?? "general-purpose",
            json["description"] as? String ?? json["prompt"] as? String ?? ""
        )
    }

    func parseAskUserQuestionInput(_ input: String?) -> [PromptEntry.PromptQuestion] {
        guard let json = Self.parsedJSONDictionary(from: input),
              let questions = json["questions"] as? [[String: Any]] else {
            return []
        }

        return questions.compactMap { question -> PromptEntry.PromptQuestion? in
            guard let text = question["question"] as? String else {
                return nil
            }

            let options = (question["options"] as? [[String: Any]] ?? []).compactMap { option -> PromptEntry.PromptOption? in
                guard let label = option["label"] as? String else {
                    return nil
                }

                return PromptEntry.PromptOption(
                    label: label,
                    description: option["description"] as? String ?? "",
                    isCustomResponse: (option["allowCustomResponse"] as? Bool ?? false)
                        || label.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Other") == .orderedSame
                )
            }

            return PromptEntry.PromptQuestion(
                question: text,
                header: question["header"] as? String,
                options: options,
                multiSelect: question["multiSelect"] as? Bool ?? false,
                allowsCustomResponse: question["allowCustomResponse"] as? Bool ?? true
            )
        }
    }

    func cachedToolSummary(toolId: String, name: String?, input: String?) -> String {
        if let cachedSummary = summaryCache[toolId] {
            return cachedSummary
        }

        let summary = Self.toolSummary(name: name, input: input)
        summaryCache[toolId] = summary
        return summary
    }
}

private extension ChatItemGrouper {
    static func skillToolSummary(name: String?, input: String?) -> String? {
        guard name == "Skill" else {
            return nil
        }

        return skillSummary(from: parsedJSONDictionary(from: input))
    }

    static func parsedJSONDictionary(from input: String?) -> [String: Any]? {
        guard let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return json
    }

    static func readToolSummary(from json: [String: Any]) -> String {
        let path = json["file_path"] as? String ?? ""
        // Collapse the user's home directory to `~` for readability without losing the
        // full canonical location (users want to see the directory context, not just the
        // bare filename).
        let display = (path as NSString).abbreviatingWithTildeInPath
        if let offset = json["offset"] as? Int,
           let limit = json["limit"] as? Int {
            return "Read `\(display):\(offset)-\(offset + limit - 1)`"
        }

        return "Read `\(display)`"
    }

    static func fileMutationToolSummary(name: String, json: [String: Any]) -> String {
        let path = json["file_path"] as? String ?? ""
        let fileName = (path as NSString).lastPathComponent
        return "\(name) `\(fileName)`"
    }

    static func commandToolSummary(name: String, json: [String: Any]) -> String {
        guard let command = CommandToolPresentation.command(fromJSON: json) else {
            return name
        }
        return CommandToolPresentation.executingSummary(command: command)
    }

    /// `ToolSearch.query` is either `select:<Name>[,<Name>...]` to pull specific tool schemas,
    /// or a freeform keyword string. Strip the `select:` prefix when present, split comma-separated
    /// names into separate inline-code spans, and pluralize the summary for multi-tool lookups.
    static func toolSearchSummary(from json: [String: Any]) -> String {
        let query = json["query"] as? String ?? ""
        let rawDisplay: String
        if query.hasPrefix("select:") {
            rawDisplay = String(query.dropFirst("select:".count))
        } else {
            rawDisplay = query
        }

        let displays = rawDisplay
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard displays.count > 1 else {
            return "Searching for tool `\(displays.first ?? rawDisplay)`"
        }

        return "Searching for tools \(formattedToolSearchList(displays))"
    }

    static func formattedToolSearchList(_ displays: [String]) -> String {
        let formattedDisplays = displays.map { "`\($0)`" }
        switch formattedDisplays.count {
        case 0:
            return ""
        case 1:
            return formattedDisplays[0]
        case 2:
            return formattedDisplays.joined(separator: " and ")
        default:
            let leadingDisplays = formattedDisplays.dropLast().joined(separator: ", ")
            guard let lastDisplay = formattedDisplays.last else {
                return ""
            }
            return "\(leadingDisplays), and \(lastDisplay)"
        }
    }

    static func skillSummary(from json: [String: Any]?) -> String {
        guard let skill = json?["skill"] as? String else {
            return "Invoking skill"
        }

        let trimmedSkill = skill.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSkill.isEmpty else {
            return "Invoking skill"
        }

        return "Invoking skill `\(trimmedSkill)`"
    }

    static func todoWriteSummary(from json: [String: Any]) -> String {
        let todos = json["todos"] as? [[String: Any]] ?? []
        let completedCount = todos.filter { ($0["status"] as? String) == "completed" }.count
        return "\(completedCount)/\(todos.count) tasks"
    }
}

struct CodexFileChangePresentation: Equatable {
    struct Change: Equatable {
        let path: String
        let diff: String
        let kind: Kind

        var displayPath: String {
            (path as NSString).abbreviatingWithTildeInPath
        }

        var fileName: String {
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? displayPath : name
        }

        var detailTitle: String {
            switch kind {
            case .add, .delete:
                return displayPath
            case .update(let movePath):
                guard let movePath else {
                    return displayPath
                }
                let source = (movePath as NSString).abbreviatingWithTildeInPath
                return "\(source) -> \(displayPath)"
            case .unknown(let raw):
                return "\(displayPath) (kind: \(raw))"
            }
        }

        var contentLanguage: String {
            isUnifiedDiff ? "diff" : FileLanguageHint.language(forPath: path)
        }

        private var isUnifiedDiff: Bool {
            let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("@@") || trimmed.hasPrefix("diff --git") || trimmed.contains("\n@@")
        }
    }

    enum Kind: Equatable {
        case add
        case delete
        case update(movePath: String?)
        case unknown(String)

        init(type: String, movePath: String?) {
            switch type {
            case "add":
                self = .add
            case "delete":
                self = .delete
            case "update":
                let trimmedMovePath = movePath?.trimmingCharacters(in: .whitespacesAndNewlines)
                self = .update(movePath: trimmedMovePath?.isEmpty == false ? trimmedMovePath : nil)
            default:
                self = .unknown(type)
            }
        }
    }

    let changes: [Change]

    static func extract(from tool: ToolEntry) -> CodexFileChangePresentation? {
        guard tool.name == "FileChange",
              let json = parsedJSON(from: tool.input) else {
            return nil
        }
        return parse(from: json)
    }

    static func parse(from json: [String: Any]) -> CodexFileChangePresentation? {
        guard let rawChanges = json["changes"] as? [[String: Any]] else {
            return nil
        }
        let changes = rawChanges.map(Change.init(json:))
        guard !changes.contains(nil) else {
            return nil
        }
        let parsedChanges = changes.compactMap { $0 }
        return parsedChanges.isEmpty ? nil : CodexFileChangePresentation(changes: parsedChanges)
    }

    func rowSummary(isComplete: Bool) -> String {
        guard changes.count == 1, let change = changes.first else {
            return isComplete ? "Changed \(changes.count) files" : "Changing \(changes.count) files"
        }
        switch change.kind {
        case .add:
            return "\(isComplete ? "Added" : "Adding") `\(change.fileName)`"
        case .delete:
            return "\(isComplete ? "Deleted" : "Deleting") `\(change.fileName)`"
        case .update(let movePath):
            if let movePath {
                let sourceName = (movePath as NSString).lastPathComponent
                let displaySource = sourceName.isEmpty ? (movePath as NSString).abbreviatingWithTildeInPath : sourceName
                return "\(isComplete ? "Moved" : "Moving") `\(displaySource)` to `\(change.fileName)`"
            }
            return "\(isComplete ? "Updated" : "Updating") `\(change.fileName)`"
        case .unknown:
            return "\(isComplete ? "Changed" : "Changing") `\(change.fileName)`"
        }
    }

    private static func parsedJSON(from input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

private extension CodexFileChangePresentation.Change {
    init?(json: [String: Any]) {
        guard let path = json["path"] as? String,
              let diff = json["diff"] as? String,
              let kind = json["kind"] as? [String: Any],
              let type = kind["type"] as? String else {
            return nil
        }
        self.path = path
        self.diff = diff
        self.kind = CodexFileChangePresentation.Kind(type: type, movePath: kind["move_path"] as? String)
    }
}
