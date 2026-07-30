import BlockInputKit
import XCTest

@testable import Alveary

final class AppMarkdownImagePreviewActionTests: XCTestCase {
    /// Equality must exclude the closure so hosts can rebuild the action every
    /// render without invalidating the markdown subtree's environment.
    func testEqualityComparesOnlyTheStableID() {
        let first = AppMarkdownImagePreviewAction(id: "modal") { _, _ in }
        let second = AppMarkdownImagePreviewAction(id: "modal") { _, _ in }
        let other = AppMarkdownImagePreviewAction(id: "different") { _, _ in }

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
    }

    @MainActor
    func testCallAsFunctionForwardsImageAndBaseURL() {
        let received = ReceivedOpen()
        let action = AppMarkdownImagePreviewAction(id: "modal") { image, baseURL in
            received.image = image
            received.baseURL = baseURL
        }
        let image = BlockInputImage(source: "https://example.com/photo.png", altText: "Photo")
        let baseURL = URL(fileURLWithPath: "/tmp", isDirectory: true)

        action(image, baseURL: baseURL)

        XCTAssertEqual(received.image?.source, "https://example.com/photo.png")
        XCTAssertEqual(received.baseURL, baseURL)
    }
}

/// Reference box because the action's closure is `@Sendable` and cannot
/// capture a mutable local.
@MainActor
private final class ReceivedOpen {
    var image: BlockInputImage?
    var baseURL: URL?
}
