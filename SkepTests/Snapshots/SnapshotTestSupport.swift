import AppKit
import SnapshotTesting
import SwiftUI
import XCTest

@MainActor
func assertMacSnapshot<V: View>(
    _ view: V,
    size: CGSize,
    named: String? = nil,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    let isRecordingSnapshots = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

    let rootView = view
        .transaction { $0.animation = nil }
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.colorScheme, .light)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))

    let controller = NSHostingController(rootView: rootView)
    controller.view.frame = CGRect(origin: .zero, size: size)
    controller.view.appearance = NSAppearance(named: .aqua)
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    window.backgroundColor = .windowBackgroundColor
    window.contentViewController = controller
    window.layoutIfNeeded()
    window.displayIfNeeded()
    controller.view.layoutSubtreeIfNeeded()
    controller.view.displayIfNeeded()

    assertSnapshot(
        of: controller,
        as: .image,
        named: named,
        record: isRecordingSnapshots ? true : nil,
        file: file,
        testName: testName,
        line: line
    )
}
