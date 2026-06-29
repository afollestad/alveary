@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollBridgeTests {
    func testFileAttachmentOnlyContentChangeReconfiguresContainer() async {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        container.layoutSubtreeIfNeeded()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items: [ChatItem] = [.userMessage(id: "user-file", text: "")]

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: .init(),
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        let emptyHeight = container.documentHeight
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.transcriptFileAttachmentsByMessageID = [
            "user-file": [bridgeFileAttachment(label: "report.pdf")]
        ]

        coordinator.update(
            container: container,
            items: items,
            rowConfiguration: configuration,
            isFollowing: false,
            scrollToBottomRequest: 0
        )
        for _ in 0..<100 where container.documentHeight <= emptyHeight + 1 {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertGreaterThan(container.documentHeight, emptyHeight + 1)
    }
}

private func bridgeFileAttachment(label: String) -> LocalFileAttachment {
    LocalFileAttachment(
        id: label,
        fileURL: URL(fileURLWithPath: "/tmp/\(label)"),
        label: label,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}
