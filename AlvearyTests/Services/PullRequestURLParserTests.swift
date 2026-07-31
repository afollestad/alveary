import XCTest

@testable import Alveary

final class PullRequestURLParserTests: XCTestCase {
    func testParsesCanonicalPullRequestURL() {
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42"),
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
        )
    }

    func testParsesURLWithTrailingPathAndFragment() {
        let expected = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42/files"),
            expected
        )
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42/commits/abc123"),
            expected
        )
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42#issuecomment-99"),
            expected
        )
    }

    /// Browser-copied URLs carry tab paths and query parameters; the identifier
    /// normalizes all of it away, so the link is just owner/repo#number and the
    /// stored URL is GitHub's canonical one from the validating fetch.
    func testParsesURLWithQueryParameters() {
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/afollestad/af.codes/pull/5/changes?t=1"),
            PullRequestIdentifier(owner: "afollestad", repo: "af.codes", number: 5)
        )
        let expected = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42?w=1"),
            expected
        )
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42/files?diff=split#diff-abc"),
            expected
        )
    }

    /// A URL copied out of a browser's address bar often loses its scheme, and
    /// `URL` reports no host without one.
    func testParsesURLWithoutSchemeAndWithWWWHost() {
        let expected = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
        XCTAssertEqual(PullRequestURLParser.identifier(from: "github.com/octo/alpha/pull/42"), expected)
        XCTAssertEqual(PullRequestURLParser.identifier(from: "https://WWW.GitHub.com/octo/alpha/pull/42"), expected)
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "  https://github.com/octo/alpha/pull/42\n"),
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
        )
    }

    func testParsesDisplayKeyShorthand() {
        XCTAssertEqual(
            PullRequestURLParser.identifier(from: "octo/alpha#42"),
            PullRequestIdentifier(owner: "octo", repo: "alpha", number: 42)
        )
    }

    func testRejectsNonGitHubHosts() {
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://gitlab.com/octo/alpha/pull/42"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com.evil.test/octo/alpha/pull/42"))
    }

    func testRejectsNonPullRequestGitHubURLs() {
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com/octo/alpha"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/issues/42"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull"))
    }

    /// `Int` would happily read "42abc" as nil but "+42" as 42, and a zero or
    /// negative number is not a pull request either.
    func testRejectsMalformedNumbers() {
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/42abc"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/+42"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "https://github.com/octo/alpha/pull/0"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "octo/alpha#-1"))
    }

    func testRejectsMalformedShorthand() {
        XCTAssertNil(PullRequestURLParser.identifier(from: "alpha#42"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "octo/alpha#"))
        XCTAssertNil(PullRequestURLParser.identifier(from: "octo/alpha#4#2"))
    }

    func testRejectsEmptyInput() {
        XCTAssertNil(PullRequestURLParser.identifier(from: ""))
        XCTAssertNil(PullRequestURLParser.identifier(from: "   "))
    }
}
