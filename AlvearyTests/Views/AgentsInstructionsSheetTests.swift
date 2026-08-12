import AppKit
import BlockInputKit
import SwiftUI
import XCTest

@testable import Alveary

/// The `AGENTS.md` sheet reloads its document from disk while it is on screen, which
/// only works because the editor host is keyed on `contentGeneration`. Nothing else
/// invalidates it — the host's one stored property is a reference whose pointer never
/// changes — so a dropped key leaves Revert showing the pre-revert text.
@MainActor
final class AgentsInstructionsSheetTests: XCTestCase {
    func testRevertRebuildsTheMountedEditor() async throws {
        let service = StubInstructionsService(shared: "# On disk\n")
        let model = GlobalInstructionsEditorModel(service: service, agentRegistry: DefaultAgentRegistry())
        await model.loadIfNeeded()

        let host = mountSheet(model: model)
        defer { host.tearDown() }
        await host.settle()

        let original = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))

        await model.revert()
        await host.settle()

        let rebuilt = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))
        XCTAssertFalse(
            rebuilt === original,
            "Revert reused the mounted editor, so it keeps showing the text it was supposed to discard"
        )
    }

    @MainActor
    private struct Host {
        let window: NSWindow
        let hosting: NSHostingView<AnyView>

        func settle() async {
            for _ in 0..<40 {
                hosting.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                await Task.yield()
            }
        }

        func tearDown() {
            window.contentView = nil
        }
    }

    private func mountSheet(model: GlobalInstructionsEditorModel) -> Host {
        let size = NSRect(x: 0, y: 0, width: 720, height: 620)
        let hosting = NSHostingView(
            rootView: AnyView(
                AgentsInstructionsEditorSheet(model: model, onCancel: {}, onSaved: {})
            )
        )
        hosting.frame = size
        let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return Host(window: window, hosting: hosting)
    }

    private static func firstBlockInputView(in view: NSView) -> BlockInputView? {
        if let match = view as? BlockInputView {
            return match
        }
        return view.subviews.lazy.compactMap { firstBlockInputView(in: $0) }.first
    }
}
