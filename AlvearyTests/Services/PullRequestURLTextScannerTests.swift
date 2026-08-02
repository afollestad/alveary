import XCTest

@testable import Alveary

final class PullRequestURLTextScannerTests: XCTestCase {
    func testFindsBareURLInProse() {
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "Opened https://github.com/octo/alpha/pull/42 for review."),
            [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        )
    }

    func testFindsSchemelessURL() {
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "see github.com/octo/alpha/pull/7 please"),
            [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)]
        )
    }

    func testFindsURLInsideMarkdownLink() {
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "[the PR](https://github.com/octo/alpha/pull/42)"),
            [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        )
    }

    func testFindsURLInsideAngleBrackets() {
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "<https://github.com/octo/alpha/pull/42>"),
            [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        )
    }

    /// The parser rejects a number segment with any trailing non-digit, so prose
    /// punctuation has to come off before it sees the candidate.
    func testTrimsTrailingPunctuation() {
        let expected = [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        for text in [
            "Landed in https://github.com/octo/alpha/pull/42.",
            "Landed in https://github.com/octo/alpha/pull/42,",
            "Landed in https://github.com/octo/alpha/pull/42!",
            "Landed in **https://github.com/octo/alpha/pull/42**"
        ] {
            XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: text), expected, text)
        }
    }

    func testNormalizesTabPathsAndQueries() {
        let expected = [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "https://github.com/octo/alpha/pull/42/files#r123"),
            expected
        )
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "https://github.com/octo/alpha/pull/42?w=1"),
            expected
        )
    }

    func testReturnsEachPullRequestOnceInAppearanceOrder() {
        let text = """
        Compare https://github.com/octo/beta/pull/9 with https://github.com/octo/alpha/pull/42,
        then look at https://github.com/octo/beta/pull/9 again.
        """

        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: text),
            [
                PullRequestIdentifier(owner: "octo", repo: "beta", number: 9),
                PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
            ]
        )
    }

    /// `PullRequestURLParser` accepts the shorthand, but in prose `owner/repo#123`
    /// is far more often an issue reference, so the scanner must not match it.
    func testIgnoresShorthandReferences() {
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "fixes octo/alpha#42"), [])
    }

    func testIgnoresNonPullRequestGitHubURLs() {
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://github.com/octo/alpha/issues/42"), [])
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://github.com/octo/alpha"), [])
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://gitlab.com/octo/alpha/pull/42"), [])
    }

    /// The scanner searches inside prose, so a lookalike host must not let its
    /// `github.com/...` tail match on its own.
    func testIgnoresLookalikeHosts() {
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://github.com.evil.test/octo/alpha/pull/42"), [])
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://evilgithub.com/octo/alpha/pull/42"), [])
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://not-github.com/octo/alpha/pull/42"), [])
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "evilgithub.com/octo/alpha/pull/42"), [])
    }

    /// Real subdomain-shaped hosts still reach the parser, which accepts only
    /// `github.com` and `www.github.com`.
    func testAcceptsWWWHostButNotOtherSubdomains() {
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "https://www.github.com/octo/alpha/pull/42"),
            [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        )
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "https://gist.github.com/octo/alpha/pull/42"), [])
    }

    func testMatchesUppercaseHost() {
        XCTAssertEqual(
            PullRequestURLTextScanner.identifiers(in: "HTTPS://GITHUB.COM/octo/alpha/pull/42"),
            [PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)]
        )
    }

    func testIgnoresTextWithoutLinks() {
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: "No links here at all."), [])
        XCTAssertEqual(PullRequestURLTextScanner.identifiers(in: ""), [])
    }
}
