struct DiffLine: Sendable, Equatable, Codable {
    let type: LineType
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    /// Raw-valued so the synthesized `Codable` conformance covers it: a review proposal's narrowed
    /// hunks are persisted by `PullRequestReviewProposalPreviewCache`, and a case-index encoding
    /// would silently remap if the cases were ever reordered.
    enum LineType: String, Sendable, Equatable, Codable {
        case context
        case added
        case deleted
    }
}
