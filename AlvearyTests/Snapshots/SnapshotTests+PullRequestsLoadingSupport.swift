import SnapshotTesting
import SwiftUI
import XCTest

@testable import Alveary

/// Keep the real screen mounted through its appearance load; a failed preload is retried on mount.
@MainActor
final class PullRequestsUnavailableSnapshotHost {
    private let viewModel: PullRequestsViewModel
    private let controller: NSHostingController<AnyView>
    private let window: NSWindow

    init(viewModel: PullRequestsViewModel) {
        self.viewModel = viewModel
        let size = CGSize(width: 1_120, height: 900)
        let root = PullRequestsScreen(viewModel: viewModel, onOpenGitSettings: {})
            .transaction { $0.animation = nil }
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.colorScheme, .light)
            .environment(\.statusSpinnerAnimationsDisabled, true)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        controller = NSHostingController(rootView: AnyView(root))
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: .aqua)
        window = NSWindow(
            contentRect: CGRect(x: -2_120, y: -1_900, width: size.width, height: size.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = controller
        layout()
    }

    func requireNotInstalled(loadCompleted: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !loadCompleted() || viewModel.loadPhase != .unavailable(.notInstalled), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try XCTUnwrap(
            loadCompleted() && viewModel.loadPhase == .unavailable(.notInstalled) ? true : nil,
            "Expected every screen load to finish with GitHub CLI not installed"
        )
        layout()
        for label in ["GitHub CLI not installed", "Open Git Settings"] {
            try requireSnapshotAccessibilityLabel(label, in: controller.view, pump: {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                self.layout()
            })
        }
        _ = try XCTUnwrap(viewModel.loadPhase == .unavailable(.notInstalled) ? true : nil)
    }

    func assertSnapshot(named: String, file: StaticString, testName: String, line: UInt = #line) {
        layout()
        SnapshotTesting.assertSnapshot(
            of: controller, as: macSnapshotImage(), named: named,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? true : nil,
            file: file, testName: testName, line: line
        )
    }

    func close() { closeSnapshotWindow(window, controller: controller) }

    private func layout() {
        window.makeFirstResponder(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
    }
}
