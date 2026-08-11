import Foundation

/// Turns what a user can paste into a `PullRequestIdentifier`. Pure — validating
/// that the pull request actually exists is the caller's job, through
/// `PullRequestsService.fetchDetail(_:)`.
enum PullRequestURLParser {
    /// Accepts a github.com pull-request URL, with or without a scheme and with
    /// any trailing path, query, or fragment (`/files`, `/changes?t=1`,
    /// `#issuecomment-1`), or the `owner/repo#123` shorthand that
    /// `PullRequestIdentifier.displayKey` renders. The identifier is the whole
    /// result — everything past the number normalizes away, and the canonical
    /// URL comes from the validating fetch, never the pasted text.
    static func identifier(from text: String) -> PullRequestIdentifier? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return identifierFromShorthand(trimmed) ?? identifierFromURL(trimmed)
    }

    private static func identifierFromShorthand(_ text: String) -> PullRequestIdentifier? {
        let parts = text.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let number = pullRequestNumber(from: parts[1]) else {
            return nil
        }
        return PullRequestIdentifier(nameWithOwner: String(parts[0]), number: number)
    }

    private static func identifierFromURL(_ text: String) -> PullRequestIdentifier? {
        // A pasted URL often arrives without a scheme; `URL` needs one to
        // populate `host` and `pathComponents`.
        let normalized = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: normalized),
              let host = url.host()?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            return nil
        }

        // ["/", owner, repo, "pull", number, …trailing]
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 4,
              components[2] == "pull",
              let number = pullRequestNumber(from: components[3]) else {
            return nil
        }
        return PullRequestIdentifier(owner: components[0], repo: components[1], number: number)
    }

    /// Rejects anything but plain digits, so `12x` or a negative number cannot
    /// slip through `Int`'s more permissive parsing.
    private static func pullRequestNumber(from text: some StringProtocol) -> Int? {
        guard !text.isEmpty,
              text.allSatisfy(\.isASCII),
              text.allSatisfy(\.isNumber),
              let number = Int(text),
              number > 0 else {
            return nil
        }
        return number
    }
}
