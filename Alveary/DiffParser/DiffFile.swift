struct DiffFile: Sendable, Equatable {
    let oldPath: String?
    let newPath: String?
    let isBinary: Bool
    let isRenamed: Bool
    let hunks: [DiffHunk]

    var path: String {
        newPath ?? oldPath ?? "(unknown)"
    }

    var linesAdded: Int {
        hunks.reduce(0) { $0 + $1.linesAdded }
    }

    var linesDeleted: Int {
        hunks.reduce(0) { $0 + $1.linesDeleted }
    }
}
