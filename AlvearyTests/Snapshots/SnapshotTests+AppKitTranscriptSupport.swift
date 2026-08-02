import AppKit
import SwiftUI
import XCTest

@testable import Alveary

/// Shared host for AppKit transcript row snapshots, used by the transcript
/// snapshot companions.
@MainActor
extension SnapshotTests {
    func appKitRowSnapshot<Content: NSView>(
        _ makeContent: @escaping () -> Content
    ) -> some View {
        AppKitTranscriptSnapshotHost(makeContent: makeContent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AppKitTranscriptSnapshotHost<Content: NSView>: NSViewRepresentable {
    let makeContent: () -> Content

    func makeNSView(context: Context) -> AppKitTranscriptSnapshotContainerView {
        AppKitTranscriptSnapshotContainerView(contentView: makeContent())
    }

    func updateNSView(_ nsView: AppKitTranscriptSnapshotContainerView, context: Context) {
        nsView.needsLayout = true
    }
}

final class AppKitTranscriptSnapshotContainerView: NSView {
    private let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: .zero)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
        contentView.layoutSubtreeIfNeeded()
    }
}
