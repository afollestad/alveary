import Foundation

/// Whole-file progressive loading policy for PR diffs: only a prefix window of files is
/// rendered ("Show more files" grows it) and big files start collapsed to their header.
/// The window bounds row-model memory and layout cost; the parsed `[DiffFile]` array
/// stays whole in the pane session (bounded upstream by the 5 MB raw-diff cap).
enum PullRequestDiffFilePaging {
    static let initialFileCount = 15
    static let fileCountStep = 15
    static let autoCollapseChangedLineThreshold = 400

    static func renderedFiles(_ files: [DiffFile], renderedFileCount: Int) -> [DiffFile] {
        Array(files.prefix(max(0, renderedFileCount)))
    }

    static func remainingFileCount(total: Int, renderedFileCount: Int) -> Int {
        max(0, total - max(0, renderedFileCount))
    }

    static func nextRenderedFileCount(current: Int, total: Int) -> Int {
        min(max(0, current) + fileCountStep, total)
    }

    /// Files whose changed-line count exceeds the threshold start collapsed. Indices are
    /// window-stable because the rendered window is always a prefix of the parsed array.
    static func autoCollapsedFileIDs(for files: [DiffFile]) -> Set<String> {
        var ids = Set<String>()
        for (index, file) in files.enumerated()
        where file.linesAdded + file.linesDeleted > autoCollapseChangedLineThreshold {
            ids.insert(FlattenedDiffPreviewRows.fileCollapseID(for: file, fileIndex: index))
        }
        return ids
    }
}
