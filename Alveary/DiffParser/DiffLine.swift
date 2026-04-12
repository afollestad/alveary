struct DiffLine: Sendable, Equatable {
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    enum LineType: Sendable, Equatable {
        case context
        case added
        case deleted
    }
}
