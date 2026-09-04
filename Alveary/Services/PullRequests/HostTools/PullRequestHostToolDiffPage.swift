import AgentCLIKit
import Foundation

/// Accounts for both representations before accepting content. Inventory, patch bytes, and
/// threads advance only after they fit; an omitted suffix always has a continuation.
struct PullRequestHostToolDiffPage {
    let session: PullRequestHostToolDiffSession
    let cursor: PullRequestHostToolDiffCursor

    func render() throws -> AgentCLIKit.AgentHostToolResult {
        let indices = try selectedIndices()
        guard cursor.file <= indices.count, cursor.inventory <= indices.count,
              indices.isEmpty || cursor.file < indices.count || cursor.byte == 0 && cursor.thread == 0 else {
            throw PullRequestHostToolServiceError.diffOffsetOutOfRange(offset: cursor.file, fileCount: indices.count)
        }
        if cursor.file == indices.count, !indices.isEmpty, cursor.inventory == 0 {
            throw PullRequestHostToolServiceError.diffOffsetOutOfRange(offset: cursor.file, fileCount: indices.count)
        }
        var next = cursor
        var rows: [Int: [String: AgentCLIKit.JSONValue]] = [:]
        var budget = 250_000
        // Small diffs still lead with their complete inventory. Larger inventories page first.
        while next.inventory < indices.count {
            let row = metadata(indices[next.inventory])
            let cost = try JSONEncoder().encode(AgentCLIKit.JSONValue.object(row)).count * 2
            guard cost <= budget else { break }
            rows[next.inventory] = row
            budget -= cost
            next.inventory += 1
        }
        if next.inventory == indices.count {
            try appendPatches(indices: indices, next: &next, rows: &rows)
        }
        let result = try result(rows: rows, next: next, total: indices.count)
        guard try Self.byteCount(result) < 950_000 else { throw PullRequestsServiceError.responseTooLarge }
        return result
    }

    private func appendPatches(
        indices: [Int], next: inout PullRequestHostToolDiffCursor,
        rows: inout [Int: [String: AgentCLIKit.JSONValue]]
    ) throws {
        var progress = Progress(next: next, rows: rows)
        let endFile = min(indices.count, next.file + 200)
        while progress.next.file < endFile {
            guard try appendFile(index: indices[progress.next.file], total: indices.count, progress: &progress) else { break }
        }
        next = progress.next
        rows = progress.rows
    }

    private struct Progress {
        var next: PullRequestHostToolDiffCursor
        var rows: [Int: [String: AgentCLIKit.JSONValue]]
        var patchBudget = PullRequestHostToolLimits.maxPatchBytes
    }

    private func appendFile(index: Int, total: Int, progress: inout Progress) throws -> Bool {
        let entry = session.snapshot.files[index]
        let threads = session.detail.reviewThreads.filter { $0.path == entry.metadata.path }
        guard progress.next.byte <= entry.patchLength, progress.next.thread <= threads.count else {
            throw HostToolRequestError.invalidArguments("cursor is outside this file's patch or review threads.")
        }
        var row = progress.rows[progress.next.file] ?? metadata(index)
        guard try fits(row: row, progress: progress, total: total) else { return false }
        if progress.next.byte < entry.patchLength {
            guard try appendPatch(index: index, row: &row, progress: &progress, total: total) else { return false }
        }
        try appendThreads(threads, row: &row, progress: &progress, total: total)
        progress.rows[progress.next.file] = row
        guard progress.next.byte == entry.patchLength, progress.next.thread == threads.count else { return false }
        progress.next.file += 1
        progress.next.byte = 0
        progress.next.thread = 0
        return true
    }

    private func appendPatch(index: Int, row: inout [String: AgentCLIKit.JSONValue], progress: inout Progress, total: Int) throws -> Bool {
        let entry = session.snapshot.files[index]
        var limit = progress.patchBudget
        while limit >= 4 {
            let fragment = try session.snapshot.fragment(file: index, offset: progress.next.byte, maxBytes: limit)
            var candidate = row
            Self.add(fragment: fragment, offset: progress.next.byte, complete: fragment.nextOffset == entry.patchLength, to: &candidate)
            if try fits(row: candidate, progress: progress, total: total) {
                row = candidate
                progress.patchBudget -= fragment.text.utf8.count
                progress.next.byte = fragment.nextOffset
                return true
            }
            limit /= 2
        }
        return false
    }

    private func appendThreads(
        _ threads: [PullRequestReviewThread], row: inout [String: AgentCLIKit.JSONValue], progress: inout Progress, total: Int
    ) throws {
        var rendered: [AgentCLIKit.JSONValue] = []
        let threadStart = progress.next.thread
        let allowance = PullRequestHostToolJSON.threadCommentAllowance(threadCount: threads.count)
        while progress.next.thread < threads.count {
            let thread = PullRequestHostToolDiffThreads.structuredThread(threads[progress.next.thread], commentAllowance: allowance)
            var candidate = row
            candidate["threads"] = .array(rendered + [thread])
            guard try fits(row: candidate, progress: progress, total: total) else { break }
            rendered.append(thread)
            progress.next.thread += 1
        }
        if !rendered.isEmpty {
            row["threads"] = .array(rendered)
            row["thread_offset"] = .number(Double(threadStart))
        }
        row["threads_truncated"] = .bool(progress.next.thread < threads.count)
    }

    private func fits(row: [String: AgentCLIKit.JSONValue], progress: Progress, total: Int) throws -> Bool {
        var rows = progress.rows
        rows[progress.next.file] = row
        return try Self.byteCount(result(rows: rows, next: progress.next, total: total)) < 850_000
    }

    private func selectedIndices() throws -> [Int] {
        let files = session.snapshot.files
        guard let paths = cursor.paths else { return Array(files.indices) }
        let requested = Set(paths)
        let indices = files.indices.filter {
            requested.contains(files[$0].metadata.path) || files[$0].metadata.oldPath.map(requested.contains) == true
        }
        let matched = Set(indices.flatMap { [files[$0].metadata.path, files[$0].metadata.oldPath].compactMap { $0 } })
        let unknown = paths.filter { !matched.contains($0) }
        guard unknown.isEmpty else { throw PullRequestHostToolServiceError.diffPathsUnknown(unknown) }
        return indices
    }

    private func metadata(_ index: Int) -> [String: AgentCLIKit.JSONValue] {
        let entry = session.snapshot.files[index]
        let file = entry.metadata
        var row: [String: AgentCLIKit.JSONValue] = [
            "path": .string(file.path), "additions": .number(Double(entry.additions)),
            "deletions": .number(Double(entry.deletions)), "is_binary": .bool(file.isBinary),
            "thread_count": .number(Double(session.detail.reviewThreads.filter { $0.path == file.path }.count))
        ]
        if file.isRenamed, let old = file.oldPath, old != file.path { row["previous_path"] = .string(old) }
        return row
    }

    private static func add(
        fragment: PullRequestDiffSnapshot.Fragment, offset: Int, complete: Bool,
        to row: inout [String: AgentCLIKit.JSONValue]
    ) {
        row["patch"] = .string(fragment.text)
        row["patch_offset"] = .number(Double(offset))
        row["patch_truncated"] = .bool(!complete)
        row["patch_starts_mid_line"] = .bool(fragment.startsMidLine)
        row["patch_ends_mid_line"] = .bool(fragment.endsMidLine)
        if let old = fragment.oldLine { row["patch_old_line"] = .number(Double(old)) }
        if let new = fragment.newLine { row["patch_new_line"] = .number(Double(new)) }
    }

    private func result(
        rows: [Int: [String: AgentCLIKit.JSONValue]], next: PullRequestHostToolDiffCursor, total: Int
    ) throws -> AgentCLIKit.AgentHostToolResult {
        let ordered = rows.keys.sorted().compactMap { rows[$0] }
        var content: [String: AgentCLIKit.JSONValue] = [
            "status": .string("ready"), "repository": .string(cursor.identifier.nameWithOwner),
            "number": .number(Double(cursor.identifier.number)), "total_files": .number(Double(total)),
            "inventory_complete": .bool(next.inventory == total),
            "patches_included": .bool(ordered.contains { $0["patch"] != nil }),
            "files": .array(ordered.map { .object($0) })
        ]
        var text = ["\(cursor.identifier.displayKey) changes \(total) file(s):"]
        text.append(contentsOf: ordered.flatMap(Self.textRows))
        if next.inventory < total || next.file < total {
            let token = try next.encoded()
            content["next_cursor"] = .string(token)
            // File offsets remain useful for initial requests, but cannot describe half a file.
            if next.byte == 0, next.thread == 0 { content["next_offset"] = .number(Double(next.file)) }
            let guidance = "More content remains. Call get_pr_diff with cursor \(token); concatenate patch fragments by path and patch_offset."
            content["guidance"] = .string(guidance)
            text.append(guidance)
        }
        return AgentCLIKit.AgentHostToolResult(text: text.joined(separator: "\n"), structuredContent: .object(content))
    }

    private static func textRows(_ row: [String: AgentCLIKit.JSONValue]) -> [String] {
        // The text fallback carries the same fields and bounds as structured content. Rendering
        // each row as JSON also escapes paths and long-line fragments without changing their bytes.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(AgentCLIKit.JSONValue.object(row)),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return [text]
    }

    private static func byteCount(_ result: AgentCLIKit.AgentHostToolResult) throws -> Int {
        result.text.utf8.count + (try result.structuredContent.map { try JSONEncoder().encode($0).count } ?? 0)
    }
}
