import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// One pull request's diff, with review threads attached to the lines they discuss.
    ///
    /// The file list is always complete, so the model can see the whole shape of the change even
    /// when the patch text does not fit; patches page by whole file from `offset`. AgentCLIKit
    /// replaces an oversized result outright rather than truncating it, so the budget is enforced
    /// here or the call fails with nothing usable in it.
    func pullRequestDiff(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let request = try parseDiff(arguments: arguments)
        let diffText = try await fetchDiff(request.identifier)
        let detail = try await fetchDetail(request.identifier)

        let files = try Self.filtered(DiffParser.parse(diffText), paths: request.paths)
        guard files.isEmpty || request.offset < files.count else {
            throw PullRequestHostToolServiceError.diffOffsetOutOfRange(
                offset: request.offset,
                fileCount: files.count
            )
        }
        // Outdated threads anchor to lines this diff no longer has, so they would attach to
        // nothing; the pane drops them for the same reason.
        let threadsByPath = Dictionary(
            grouping: detail.reviewThreads.filter { !$0.isOutdated && $0.line != nil },
            by: \.path
        )
        let window = Self.patchWindow(files: files, from: request.offset)

        let rows = files.enumerated().map { index, file in
            PullRequestHostToolDiffFileRow(
                file: file,
                threads: threadsByPath[file.path] ?? [],
                patch: window.patches[index],
                includesThreads: window.patches[index] != nil
            )
        }
        return AgentCLIKit.AgentHostToolResult(
            text: Self.diffText(identifier: request.identifier, rows: rows, window: window),
            structuredContent: .object(Self.structuredDiff(identifier: request.identifier, rows: rows, window: window))
        )
    }
}

/// The patch text chosen for one call: which files it covers, and where a follow-up call resumes.
private struct PullRequestHostToolDiffWindow {
    /// Rendered patch per file index; nil for files outside the window.
    var patches: [Int: PullRequestHostToolRenderedPatch]
    var nextOffset: Int?

    var includesPatches: Bool {
        !patches.isEmpty
    }
}

private struct PullRequestHostToolRenderedPatch {
    let text: String
    let wasTruncated: Bool
}

/// One `get_pr_diff` file row, rendered identically into `structuredContent` and the text fallback.
private struct PullRequestHostToolDiffFileRow {
    let file: DiffFile
    let threads: [PullRequestReviewThread]
    let patch: PullRequestHostToolRenderedPatch?
    let includesThreads: Bool

    var structuredRow: AgentCLIKit.JSONValue {
        var row: [String: AgentCLIKit.JSONValue] = [
            "path": .string(file.path),
            "additions": .number(Double(file.linesAdded)),
            "deletions": .number(Double(file.linesDeleted)),
            "is_binary": .bool(file.isBinary),
            "thread_count": .number(Double(threads.count))
        ]
        if file.isRenamed, let oldPath = file.oldPath, oldPath != file.path {
            row["previous_path"] = .string(oldPath)
        }
        if let patch {
            row["patch"] = .string(patch.text)
            row["patch_truncated"] = .bool(patch.wasTruncated)
        }
        if includesThreads, !threads.isEmpty {
            row["threads"] = .array(threads.map(Self.structuredThread))
        }
        return .object(row)
    }

    var textRows: [String] {
        var rows = ["- \(summaryLine)"]
        if let patch {
            rows.append(patch.text)
        }
        if includesThreads {
            rows.append(contentsOf: threads.map(Self.threadText))
        }
        return rows
    }

    private var summaryLine: String {
        var parts = ["+\(file.linesAdded)/-\(file.linesDeleted)"]
        if file.isBinary {
            parts.append("binary")
        }
        if !threads.isEmpty {
            parts.append("\(threads.count) review thread(s)")
        }
        return "\(file.path) (\(parts.joined(separator: ", ")))"
    }

    private static func structuredThread(_ thread: PullRequestReviewThread) -> AgentCLIKit.JSONValue {
        var row: [String: AgentCLIKit.JSONValue] = [
            "is_resolved": .bool(thread.isResolved),
            "is_outdated": .bool(thread.isOutdated),
            "is_pending": .bool(thread.isPending),
            // GitHub takes no reply until a pending review is submitted, so saying so here keeps
            // the model from calling reply_to_pr_thread on a draft.
            "can_reply": .bool(thread.replyTargetCommentID != nil),
            "comments": .array(thread.comments.map(Self.structuredComment))
        ]
        if let nodeID = thread.nodeID {
            row["thread_id"] = .string(nodeID)
        }
        if let line = thread.line {
            row["line"] = .number(Double(line))
        }
        row["side"] = .string(thread.side.rawValue)
        return .object(row)
    }

    private static func structuredComment(_ comment: PullRequestComment) -> AgentCLIKit.JSONValue {
        let body = PullRequestHostToolJSON.truncated(
            comment.bodyMarkdown,
            limit: PullRequestHostToolLimits.maxBodyCharacters
        )
        var row: [String: AgentCLIKit.JSONValue] = [
            "author": PullRequestHostToolJSON.author(
                login: comment.authorLogin,
                avatarURL: comment.authorAvatarURL
            ),
            "body_markdown": .string(body.text),
            "body_truncated": .bool(body.wasTruncated),
            "is_bot": .bool(comment.isBot),
            "is_pending": .bool(comment.isPending)
        ]
        if let createdAt = comment.createdAt {
            row["created_at"] = .string(PullRequestHostToolDates.canonical(createdAt))
        }
        if !comment.reactions.isEmpty {
            row["reactions"] = PullRequestHostToolJSON.reactions(comment.reactions)
        }
        return .object(row)
    }

    private static func threadText(_ thread: PullRequestReviewThread) -> String {
        var parts: [String] = []
        if let nodeID = thread.nodeID {
            parts.append("thread_id: \(nodeID)")
        }
        if let line = thread.line {
            parts.append("line \(line) \(thread.side.rawValue)")
        }
        parts.append(thread.isResolved ? "resolved" : "unresolved")
        if thread.isPending {
            parts.append("pending")
        }
        let comments = thread.comments.map { comment in
            let body = PullRequestHostToolJSON.truncated(
                comment.bodyMarkdown,
                limit: PullRequestHostToolLimits.maxBodyCharacters
            )
            return "    \(comment.authorLogin): \(body.text.replacingOccurrences(of: "\n", with: " "))"
        }
        return (["  [\(parts.joined(separator: ", "))]"] + comments).joined(separator: "\n")
    }
}

private extension PullRequestHostToolService {
    /// Narrows to the named files, matching a rename's old path too so a caller reading a rename's
    /// previous name still finds it. An unmatched name is a refusal rather than a silent empty
    /// result, because the model cannot tell those apart.
    static func filtered(_ files: [DiffFile], paths: [String]?) throws -> [DiffFile] {
        guard let paths else {
            return files
        }
        let requested = Set(paths)
        let matched = files.filter { file in
            requested.contains(file.path) || file.oldPath.map(requested.contains) == true
        }
        let matchedNames = Set(matched.flatMap { [$0.path, $0.oldPath].compactMap { $0 } })
        let unknown = paths.filter { !matchedNames.contains($0) }
        guard unknown.isEmpty else {
            throw PullRequestHostToolServiceError.diffPathsUnknown(unknown)
        }
        return matched
    }

    /// Fills the byte budget with whole files from `offset`. A single file too large for the whole
    /// budget still yields its leading hunks, because a truncated patch beats a file the model can
    /// never read.
    static func patchWindow(files: [DiffFile], from offset: Int) -> PullRequestHostToolDiffWindow {
        var patches: [Int: PullRequestHostToolRenderedPatch] = [:]
        var remaining = PullRequestHostToolLimits.maxPatchBytes
        var index = offset

        while index < files.count {
            let file = files[index]
            guard !file.hunks.isEmpty else {
                // Binary and metadata-only files have no patch to spend budget on; their row still
                // reports the change.
                index += 1
                continue
            }
            let full = renderPatch(hunks: file.hunks)
            let cost = full.utf8.count
            if cost <= remaining {
                patches[index] = PullRequestHostToolRenderedPatch(text: full, wasTruncated: false)
                remaining -= cost
                index += 1
                continue
            }
            guard patches.isEmpty else {
                // Something already fits; the rest belongs to the next call rather than being
                // chopped mid-file.
                break
            }
            let partial = renderPartialPatch(hunks: file.hunks, budget: remaining)
            if !partial.isEmpty {
                patches[index] = PullRequestHostToolRenderedPatch(text: partial, wasTruncated: true)
            }
            index += 1
            break
        }

        return PullRequestHostToolDiffWindow(
            patches: patches,
            nextOffset: index < files.count ? index : nil
        )
    }

    static func renderPatch(hunks: [DiffHunk]) -> String {
        hunks.map(renderHunk).joined(separator: "\n")
    }

    /// Whole hunks only: half a hunk has no valid header, and a model reading it would mis-anchor
    /// every line number after the cut.
    static func renderPartialPatch(hunks: [DiffHunk], budget: Int) -> String {
        var rendered: [String] = []
        var remaining = budget
        for hunk in hunks {
            let text = renderHunk(hunk)
            let cost = text.utf8.count + 1
            guard cost <= remaining else {
                break
            }
            rendered.append(text)
            remaining -= cost
        }
        return rendered.joined(separator: "\n")
    }

    static func renderHunk(_ hunk: DiffHunk) -> String {
        var header = "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
        if let context = hunk.header, !context.isEmpty {
            header += " \(context)"
        }
        let lines = hunk.lines.map { line in
            switch line.type {
            case .added:
                "+\(line.content)"
            case .deleted:
                "-\(line.content)"
            case .context:
                " \(line.content)"
            }
        }
        return ([header] + lines).joined(separator: "\n")
    }

    static func structuredDiff(
        identifier: PullRequestIdentifier,
        rows: [PullRequestHostToolDiffFileRow],
        window: PullRequestHostToolDiffWindow
    ) -> [String: AgentCLIKit.JSONValue] {
        var content: [String: AgentCLIKit.JSONValue] = [
            "repository": .string(identifier.nameWithOwner),
            "number": .number(Double(identifier.number)),
            "total_files": .number(Double(rows.count)),
            "patches_included": .bool(window.includesPatches),
            "files": .array(rows.map(\.structuredRow))
        ]
        if let nextOffset = window.nextOffset {
            content["next_offset"] = .number(Double(nextOffset))
            content["guidance"] = .string(guidance(nextOffset: nextOffset, total: rows.count))
        }
        return content
    }

    static func guidance(nextOffset: Int, total: Int) -> String {
        "\(total - nextOffset) more file(s) have patch text left to read. Call get_pr_diff again " +
            "with offset \(nextOffset), or pass paths naming the files you need."
    }

    static func diffText(
        identifier: PullRequestIdentifier,
        rows: [PullRequestHostToolDiffFileRow],
        window: PullRequestHostToolDiffWindow
    ) -> String {
        var header = "\(identifier.displayKey) changes \(rows.count) file(s)"
        if !window.includesPatches, !rows.isEmpty {
            header += " (no patch text fit this response)"
        }
        var lines = [rows.isEmpty ? "\(header)." : "\(header):"]
        lines.append(contentsOf: rows.flatMap(\.textRows))
        if let nextOffset = window.nextOffset {
            lines.append(guidance(nextOffset: nextOffset, total: rows.count))
        }
        return lines.joined(separator: "\n")
    }
}
