struct DiffHunk: Sendable, Equatable {
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String?
    let lines: [DiffLine]

    var linesAdded: Int {
        lines.reduce(0) { partialResult, line in
            partialResult + (line.type == .added ? 1 : 0)
        }
    }

    var linesDeleted: Int {
        lines.reduce(0) { partialResult, line in
            partialResult + (line.type == .deleted ? 1 : 0)
        }
    }
}
