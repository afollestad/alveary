import AgentCLIKit
import Foundation

/// A `list_involved_prs` call, as recorded durably in the transcript.
///
/// The only read-only host tool with its own card: each row opens a different pull request, so the
/// list is a stack of controls rather than a lookup whose result reads as one line.
struct PullRequestListWidgetContent: Equatable {
    struct Row: Equatable, Identifiable {
        let identifier: PullRequestIdentifier
        let title: String
        let status: PullRequestStatus

        var id: String {
            identifier.displayKey
        }
    }

    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        case listed
        /// The call landed but its payload carried no readable rows — Codex emits the plain-text
        /// fallback rather than structured content. The card cannot list anything, and it must not
        /// claim there is nothing to list.
        case listedWithoutRows
        case failed
    }

    /// The scope the call asked for, echoed by the result.
    let filter: PullRequestHostToolListFilter?
    let rows: [Row]
    /// How many matched before the row cap, so the card can say what it is not showing.
    let totalCount: Int?
    /// An organization refused the token, so the list is genuinely incomplete. The card has to
    /// say so — a short list that looks complete is the failure mode here.
    let hasWarnings: Bool
    let message: String?
    let status: Status

    var hiddenRowCount: Int {
        guard let totalCount else {
            return 0
        }
        return max(0, totalCount - rows.count)
    }
}

/// Pure parsing for `list_involved_prs`'s persisted input/output JSON.
enum PullRequestListWidgetParsing {
    /// Never returns `nil`. The grouper patches a rendered widget only when its parser produces
    /// content, so declining a landed result would strand the card at "Finding pull requests…"
    /// forever; an unreadable payload becomes `.listedWithoutRows` instead.
    static func content(
        input: String?,
        output: String?,
        isError: Bool
    ) -> PullRequestListWidgetContent? {
        // The request carries only an optional filter, so an absent or unreadable input is still a
        // valid call — unlike the tools that name their subject in arguments.
        let arguments = HostToolWidgetJSON.object(from: input) ?? [:]
        let requestedFilter = HostToolWidgetJSON.string(arguments["filter"])
            .flatMap(PullRequestHostToolListFilter.init(rawValue:))
        let receipt = HostToolWidgetJSON.object(from: output).map(Receipt.init(object:))
        // Providers disagree about which half of the result they persist, and this card is
        // useless without rows, so the tool's own text fallback is parsed when the structured
        // content never arrives. `HostToolTranscriptCatalogTests+PullRequestList` runs the real
        // tool and parses its actual output, pinning the two sides of that format together.
        let fallback = receipt == nil ? output.map(TextFallback.init(text:)) : nil
        let status = status(receipt: receipt, fallback: fallback, output: output, isError: isError)

        return PullRequestListWidgetContent(
            filter: receipt?.filter ?? fallback?.filter ?? requestedFilter,
            rows: receipt?.rows ?? fallback?.rows ?? [],
            totalCount: receipt?.totalCount ?? fallback?.totalCount,
            hasWarnings: receipt?.hasWarnings ?? fallback?.hasWarnings ?? false,
            message: HostToolWidgetJSON.plainText(from: output),
            status: status
        )
    }
}

/// Reads the rows out of `list_involved_prs`' plain-text fallback, for providers that persist it
/// instead of the structured content. The shapes come from
/// `PullRequestHostToolService+Listing.swift`, which owns them.
private struct TextFallback {
    let filter: PullRequestHostToolListFilter?
    let rows: [PullRequestListWidgetContent.Row]
    let totalCount: Int?
    let hasWarnings: Bool

    init(text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let header = lines.first ?? ""
        filter = PullRequestHostToolListFilter.allCases.first { header.contains("(\($0.rawValue))") }
        totalCount = Self.leadingCount(in: header)
        hasWarnings = header.contains(Self.warningMarker)
        rows = lines.compactMap(Self.row(from:))
    }

    /// `"Found 32 pull requests (all)"` — the count the card compares against its rows.
    static func leadingCount(in header: String) -> Int? {
        guard header.hasPrefix("Found ") else {
            return nil
        }
        return Int(header.dropFirst("Found ".count).prefix { $0.isNumber })
    }

    /// `"- owner/repo#12 Some title (open, by someone, +3/-1)"`. The identifier comes from the
    /// shared URL parser, which already accepts the `owner/repo#number` shorthand.
    static func row(from line: String) -> PullRequestListWidgetContent.Row? {
        guard line.hasPrefix("- ") else {
            return nil
        }
        let body = line.dropFirst(2)
        guard let separator = body.firstIndex(of: " "),
              let identifier = PullRequestURLParser.identifier(from: String(body[body.startIndex..<separator])) else {
            return nil
        }
        let remainder = body[body.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        // The trailing "(status, by author, +n/-m)" is metadata, not part of the title.
        guard remainder.hasSuffix(")"), let metadataStart = remainder.lastIndex(of: "(") else {
            return PullRequestListWidgetContent.Row(
                identifier: identifier,
                title: remainder.isEmpty ? identifier.displayKey : remainder,
                status: .open
            )
        }
        let title = remainder[remainder.startIndex..<metadataStart].trimmingCharacters(in: .whitespaces)
        let metadata = remainder[remainder.index(after: metadataStart)...].dropLast()
        let status = metadata.split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap(PullRequestStatus.init(rawValue:))
        return PullRequestListWidgetContent.Row(
            identifier: identifier,
            title: title.isEmpty ? identifier.displayKey : title,
            status: status ?? .open
        )
    }

    static let warningMarker = "Some results were unavailable"
}

private extension PullRequestListWidgetParsing {
    struct Receipt {
        let filter: PullRequestHostToolListFilter?
        let rows: [PullRequestListWidgetContent.Row]
        let totalCount: Int?
        let hasWarnings: Bool

        init(object: [String: AgentCLIKit.JSONValue]) {
            filter = HostToolWidgetJSON.string(object["filter"])
                .flatMap(PullRequestHostToolListFilter.init(rawValue:))
            totalCount = HostToolWidgetJSON.integer(object["total_count"])
            if case .array(let warnings)? = object["warnings"] {
                hasWarnings = !warnings.isEmpty
            } else {
                hasWarnings = false
            }
            guard case .array(let rawRows)? = object["pull_requests"] else {
                rows = []
                return
            }
            rows = rawRows.compactMap(Self.row(from:))
        }

        /// A row without a resolvable identifier cannot be opened, so it is dropped rather than
        /// rendered as an inert line the user would click at.
        static func row(from value: AgentCLIKit.JSONValue) -> PullRequestListWidgetContent.Row? {
            guard case .object(let object) = value,
                  let repository = HostToolWidgetJSON.string(object["repository"]),
                  let number = HostToolWidgetJSON.integer(object["number"]),
                  let identifier = PullRequestIdentifier(nameWithOwner: repository, number: number) else {
                return nil
            }
            return PullRequestListWidgetContent.Row(
                identifier: identifier,
                title: HostToolWidgetJSON.string(object["title"]) ?? identifier.displayKey,
                status: HostToolWidgetJSON.string(object["status"])
                    .flatMap(PullRequestStatus.init(rawValue:)) ?? .open
            )
        }
    }

    static func status(
        receipt: Receipt?,
        fallback: TextFallback?,
        output: String?,
        isError: Bool
    ) -> PullRequestListWidgetContent.Status {
        guard let output, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        if isError {
            return .failed
        }
        if receipt != nil {
            // Structured content is authoritative, including when it lists nothing.
            return .listed
        }
        // Only the text arrived: rows found means the fallback was readable, none means we cannot
        // tell an empty result from a shape we do not recognize.
        return fallback?.rows.isEmpty == false ? .listed : .listedWithoutRows
    }
}
