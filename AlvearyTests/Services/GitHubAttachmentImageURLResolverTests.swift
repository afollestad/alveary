import Foundation
import XCTest

@testable import Alveary

@MainActor
final class GitHubAttachmentImageURLResolverTests: XCTestCase {
    private static let source = "https://github.com/user-attachments/assets/c70b87ff"
    private static let signed = "https://private-user-images.githubusercontent.com/1/2-c70b87ff.jpg?jwt=abc"

    private func makeResolver(
        shell: MockShellRunner,
        path: String? = "/opt/homebrew/bin/gh",
        now: @escaping () -> Date = Date.init
    ) -> GitHubAttachmentImageURLResolver {
        GitHubAttachmentImageURLResolver(
            shellRunner: shell,
            executableResolver: PullRequestsExecutablePathResolverFake(path: path),
            now: now
        )
    }

    func testResolveMintsThroughTheMarkdownRenderAPIWithRepositoryContext() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "<p><img src=\"\(Self.signed)\"></p>")))
        let resolver = makeResolver(shell: shell)
        resolver.registerRepository("octo/alpha")

        let url = await resolver.resolveSignedURL(forSource: Self.source)

        XCTAssertEqual(url?.absoluteString, Self.signed)
        let invocation = await shell.invocations.first
        XCTAssertEqual(invocation?.executable, "/opt/homebrew/bin/gh")
        XCTAssertEqual(
            invocation?.args,
            ["api", "/markdown", "-f", "text=![a](\(Self.source))", "-f", "mode=gfm", "-f", "context=octo/alpha"]
        )
    }

    /// The render API leaves the URL unrewritten when the context repository
    /// cannot see the asset; resolution then tries the next registered one.
    func testResolveFallsThroughToTheNextRepositoryContext() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "<p><img src=\"\(Self.source)\"></p>")))
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "<p><img src=\"\(Self.signed)\"></p>")))
        let resolver = makeResolver(shell: shell)
        resolver.registerRepository("octo/older")
        resolver.registerRepository("octo/newer")

        let url = await resolver.resolveSignedURL(forSource: Self.source)

        XCTAssertEqual(url?.absoluteString, Self.signed)
        let contexts = await shell.invocations.map { $0.args.last ?? "" }
        // Most recently registered first.
        XCTAssertEqual(contexts, ["context=octo/newer", "context=octo/older"])
    }

    func testResolveIgnoresNonAttachmentSourcesWithoutInvokingTheCLI() async {
        let shell = MockShellRunner()
        let resolver = makeResolver(shell: shell)
        resolver.registerRepository("octo/alpha")

        let url = await resolver.resolveSignedURL(forSource: "https://example.com/image.png")

        XCTAssertNil(url)
        let count = await shell.invocations.count
        XCTAssertEqual(count, 0)
    }

    func testResolveServesACachedMintWhileItIsFresh() async {
        let clock = Date(timeIntervalSince1970: 5_000)
        let shell = MockShellRunner()
        await shell.enqueue(.success(pullRequestsShellResult(stdout: "<p><img src=\"\(Self.signed)\"></p>")))
        let resolver = makeResolver(shell: shell, now: { clock })
        resolver.registerRepository("octo/alpha")

        let first = await resolver.resolveSignedURL(forSource: Self.source)
        let second = await resolver.resolveSignedURL(forSource: Self.source)

        XCTAssertEqual(first, second)
        let count = await shell.invocations.count
        XCTAssertEqual(count, 1)
    }

    func testSignedURLParsingUnescapesEntitiesAndRequiresTheSignedHost() {
        let html = "<img src=\"https://private-user-images.githubusercontent.com/a.jpg?jwt=x&amp;other=y\">"
        XCTAssertEqual(
            GitHubAttachmentImageURLResolver.signedURL(inRenderedHTML: html)?.absoluteString,
            "https://private-user-images.githubusercontent.com/a.jpg?jwt=x&other=y"
        )
        XCTAssertNil(
            GitHubAttachmentImageURLResolver.signedURL(
                inRenderedHTML: "<img src=\"https://example.com/a.jpg\">"
            )
        )
    }
}
