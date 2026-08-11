import Foundation

/// Finds GitHub pull-request links inside free-form message text so the transcript
/// can offer to link them. URLs only: `PullRequestURLParser` also accepts the
/// `owner/repo#123` shorthand, but in prose that shape is far more often an issue
/// reference than a pull request, so candidates must name `github.com`.
enum PullRequestURLTextScanner {
    /// Punctuation that commonly wraps or follows a URL in prose and markdown.
    /// It must come off before parsing, because the parser rejects a number
    /// segment with any trailing non-digit.
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?'\"`)]}>*_")

    /// The leading lookbehind is load-bearing: without it the search would match the
    /// `github.com/...` tail of a lookalike host like `evilgithub.com/octo/alpha/pull/42`,
    /// and the parser — which only ever sees the matched substring — would accept it.
    private static let candidatePattern =
        #"(?<![A-Za-z0-9.-])(?:https?://)?(?:[A-Za-z0-9-]+\.)*github\.com/[^\s<>()\[\]"'`]+"#

    private static let candidateRegex = try? NSRegularExpression(pattern: candidatePattern, options: [.caseInsensitive])

    /// Returns every distinct pull request referenced by `text`, in the order the
    /// links appear.
    static func identifiers(in text: String) -> [PullRequestIdentifier] {
        guard let candidateRegex, !text.isEmpty else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var identifiers: [PullRequestIdentifier] = []
        var seen: Set<PullRequestIdentifier> = []

        for match in candidateRegex.matches(in: text, options: [], range: range) {
            guard let matchRange = Range(match.range, in: text) else {
                continue
            }
            let candidate = String(text[matchRange])
                .trimmingTrailingCharacters(in: trailingPunctuation)
            guard let identifier = PullRequestURLParser.identifier(from: candidate),
                  seen.insert(identifier).inserted else {
                continue
            }
            identifiers.append(identifier)
        }

        return identifiers
    }
}

private extension String {
    func trimmingTrailingCharacters(in characterSet: CharacterSet) -> String {
        var trimmed = Substring(self)
        while let last = trimmed.unicodeScalars.last, characterSet.contains(last) {
            trimmed = trimmed.dropLast()
        }
        return String(trimmed)
    }
}
