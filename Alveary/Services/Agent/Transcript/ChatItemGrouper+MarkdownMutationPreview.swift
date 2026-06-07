import Foundation

extension ChatItemGrouper {
    func rememberExitPlanModePlanMarkdownIfNeeded(_ approval: ToolApprovalRequest) {
        guard let planMarkdown = approval.planMarkdown else {
            return
        }
        rememberExitPlanModePlanMarkdown(planMarkdown)
    }

    func markdownMutationPreview(for tool: ToolEntry, event: ConversationEventRecord) -> ToolContentPreview? {
        guard tool.name == "Write" || tool.name == "Edit" || tool.name == "MultiEdit",
              !event.isError,
              !event.toolOutputInterrupted,
              let json = parsedToolInput(tool.input),
              let path = markdownPath(from: json) else {
            return nil
        }

        switch tool.name {
        case "Write":
            return updateMarkdownSnapshotForWrite(json: json, path: path)
        case "Edit", "MultiEdit":
            return updateMarkdownSnapshotForMutation(toolName: tool.name, json: json, path: path)
        default:
            return nil
        }
    }

    private func rememberExitPlanModePlanMarkdown(_ markdown: String) {
        let normalizedPlan = normalizedMarkdown(markdown)
        guard !normalizedPlan.isEmpty else {
            return
        }

        if !exitPlanModePlanMarkdowns.contains(normalizedPlan) {
            exitPlanModePlanMarkdowns.append(normalizedPlan)
        }

        for key in markdownSnapshotsByPath.keys {
            guard let snapshot = markdownSnapshotsByPath[key],
                  normalizedMarkdown(snapshot.content) == normalizedPlan else {
                continue
            }
            markdownSnapshotsByPath[key] = MarkdownSnapshot(
                content: snapshot.content,
                origin: .exitPlanModeFollowUp
            )
        }
    }

    private func updateMarkdownSnapshotForWrite(json: [String: Any], path: MarkdownSnapshotPath) -> ToolContentPreview? {
        guard let content = json["content"] as? String else {
            return nil
        }
        markdownSnapshotsByPath[path.key] = MarkdownSnapshot(
            content: content,
            origin: exitPlanModePreviewOrigin(for: content)
        )
        return nil
    }

    private func updateMarkdownSnapshotForMutation(
        toolName: String,
        json: [String: Any],
        path: MarkdownSnapshotPath
    ) -> ToolContentPreview? {
        guard let snapshot = snapshotForMarkdownMutation(toolName: toolName, json: json, path: path),
              let updatedContent = applyingMarkdownMutation(toolName: toolName, json: json, to: snapshot.content) else {
            return nil
        }

        markdownSnapshotsByPath[path.key] = MarkdownSnapshot(
            content: updatedContent,
            origin: snapshot.origin
        )
        return ToolContentPreview(
            content: updatedContent,
            language: "markdown",
            baseURL: path.baseURL,
            origin: snapshot.origin
        )
    }

    private func snapshotForMarkdownMutation(
        toolName: String,
        json: [String: Any],
        path: MarkdownSnapshotPath
    ) -> MarkdownSnapshot? {
        if let snapshot = markdownSnapshotsByPath[path.key] {
            return snapshot
        }
        return exitPlanModePlanSnapshotMatching(toolName: toolName, json: json)
    }

    // ExitPlanMode approvals can render a plan without tying it to a file path. A later
    // mutation may still be the plan follow-up if it applies to exactly one remembered plan.
    private func exitPlanModePlanSnapshotMatching(toolName: String, json: [String: Any]) -> MarkdownSnapshot? {
        let matchingPlans = exitPlanModePlanMarkdowns.filter { planMarkdown in
            applyingMarkdownMutation(toolName: toolName, json: json, to: planMarkdown) != nil
        }
        guard matchingPlans.count == 1,
              let planMarkdown = matchingPlans.first else {
            return nil
        }
        return MarkdownSnapshot(content: planMarkdown, origin: .exitPlanModeFollowUp)
    }

    private func exitPlanModePreviewOrigin(for content: String) -> ToolContentPreviewOrigin {
        exitPlanModePlanMarkdowns.contains(normalizedMarkdown(content))
            ? .exitPlanModeFollowUp
            : .knownMarkdownMutation
    }

    private func applyingMarkdownMutation(toolName: String, json: [String: Any], to content: String) -> String? {
        switch toolName {
        case "Edit":
            return applyingEdit(json, to: content)
        case "MultiEdit":
            return applyingMultiEdit(json, to: content)
        default:
            return nil
        }
    }

    private func applyingMultiEdit(_ json: [String: Any], to content: String) -> String? {
        guard let edits = json["edits"] as? [[String: Any]],
              !edits.isEmpty else {
            return nil
        }

        var updatedContent = content
        for edit in edits {
            guard let nextContent = applyingEdit(edit, to: updatedContent) else {
                return nil
            }
            updatedContent = nextContent
        }
        return updatedContent
    }

    private func applyingEdit(_ json: [String: Any], to content: String) -> String? {
        guard let oldString = json["old_string"] as? String,
              !oldString.isEmpty,
              let newString = json["new_string"] as? String else {
            return nil
        }

        let ranges = ranges(of: oldString, in: content)
        guard !ranges.isEmpty else {
            return nil
        }

        if json["replace_all"] as? Bool == true {
            return content.replacingOccurrences(of: oldString, with: newString)
        }

        guard ranges.count == 1,
              let range = ranges.first else {
            return nil
        }

        var updatedContent = content
        updatedContent.replaceSubrange(range, with: newString)
        return updatedContent
    }

    private func ranges(of needle: String, in haystack: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let range = haystack.range(of: needle, range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<haystack.endIndex
        }
        return ranges
    }

    private func parsedToolInput(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func markdownPath(from json: [String: Any]) -> MarkdownSnapshotPath? {
        let rawPath = (json["file_path"] as? String ?? json["path"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPath.isEmpty,
              FileLanguageHint.language(forPath: rawPath) == "markdown" else {
            return nil
        }

        let expandedPath = rawPath.hasPrefix("~")
            ? NSString(string: rawPath).expandingTildeInPath
            : rawPath

        guard expandedPath.hasPrefix("/") else {
            // Keep relative paths as transcript-local keys. Resolving them against Alveary's
            // process cwd would make restored previews depend on where the app was launched.
            return MarkdownSnapshotPath(key: expandedPath, baseURL: nil)
        }

        let normalizedPath = CanonicalPath.normalize(expandedPath)
        return MarkdownSnapshotPath(
            key: normalizedPath,
            baseURL: URL(fileURLWithPath: normalizedPath).deletingLastPathComponent()
        )
    }

    private func normalizedMarkdown(_ markdown: String) -> String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MarkdownSnapshot {
    let content: String
    let origin: ToolContentPreviewOrigin
}

private struct MarkdownSnapshotPath {
    let key: String
    let baseURL: URL?
}
