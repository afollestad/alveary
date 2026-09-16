import AppKit
import SwiftUI
import Testing

@testable import Alveary

@MainActor
extension ReviewTeamRunWidgetTests {
    @Test(.serialized, arguments: [false, true], [false, true])
    func `details dismissal preserves the opening focus presentation`(keyboard: Bool, escape: Bool) throws {
        var run = failedRun()
        let host = ReviewTeamFocusTestHost(run: run)
        defer { host.close() }
        let reviewer = try host.reviewer()

        if keyboard {
            host.window.selectKeyView(following: host.editor)
            #expect(host.window.firstResponder === reviewer)
            try host.sendKey(36, characters: "\r")
        } else {
            try host.click(reviewer)
        }
        try host.waitUntil { host.window.attachedSheet != nil }
        #expect(try host.focusMaskIsVisible(reviewer) == keyboard)

        // Progress can replace the opener while its sheet owns the key window.
        run.generation += 1
        host.configure(run: run, fontSize: 20)
        let updated = try host.reviewer()
        #expect(host.window.firstResponder === updated)
        #expect(try host.focusMaskIsVisible(updated) == keyboard)

        let sheet = try #require(host.window.attachedSheet)
        if escape {
            try host.sendKey(53, characters: "\u{1b}", to: sheet)
        } else {
            try host.pressAccessibilityButton(named: "Done", in: sheet.contentView)
        }
        try host.waitUntil { host.window.attachedSheet == nil }
        #expect(host.window.firstResponder === updated)
        #expect(try host.focusMaskIsVisible(updated) == keyboard)

        run.generation += 1
        host.configure(run: run, fontSize: 14)
        let restored = try host.reviewer()
        #expect(host.window.firstResponder === restored)
        #expect(try host.focusMaskIsVisible(restored) == keyboard)
    }

    @Test
    func `reviewer keyboard traversal exits the card and updates do not reclaim focus`() throws {
        var run = failedRun()
        let host = ReviewTeamFocusTestHost(run: run)
        defer { host.close() }
        let first = try host.reviewer()
        let second = try host.reviewer(at: 1)
        host.window.selectKeyView(following: host.editor)
        #expect(host.window.firstResponder === first)
        #expect(try host.focusMaskIsVisible(first))

        try host.sendKey(48, characters: "\t")
        #expect(host.window.firstResponder === second)
        #expect(try host.focusMaskIsVisible(second))
        try host.sendKey(48, characters: "\t", flags: .shift)
        #expect(host.window.firstResponder === first)
        try host.sendKey(48, characters: "\t", flags: .shift)
        let editorResponder = try #require(host.editor.currentEditor())
        #expect(host.window.firstResponder === editorResponder)

        run.generation += 1
        host.configure(run: run)
        #expect(host.window.firstResponder === editorResponder)
        #expect(try !host.focusMaskIsVisible(host.reviewer()))
    }

    @Test(arguments: [UInt16(36), 49, 76])
    func `reviewer activation keys reveal focus and open the requested reviewer`(key: UInt16) throws {
        let host = ReviewTeamFocusTestHost(run: failedRun())
        defer { host.close() }
        let reviewer = try host.reviewer(at: 1)
        #expect(host.window.makeFirstResponder(reviewer))
        #expect(try !host.focusMaskIsVisible(reviewer))
        let characters = key == 49 ? " " : key == 76 ? "\u{3}" : "\r"
        try host.sendKey(key, characters: characters)
        try host.waitUntil { host.window.attachedSheet != nil }
        #expect(try host.focusMaskIsVisible(reviewer))
        #expect(host.requestedReviewerID == reviewer.reviewerID)
    }

    @Test
    func `clicking a keyboard focused reviewer hides its focus mask`() throws {
        let host = ReviewTeamFocusTestHost(run: failedRun())
        defer { host.close() }
        let reviewer = try host.reviewer()
        host.window.selectKeyView(following: host.editor)
        #expect(try host.focusMaskIsVisible(reviewer))

        try host.click(reviewer)

        #expect(try !host.focusMaskIsVisible(reviewer))
        try host.waitUntil { host.window.attachedSheet != nil }
    }

    @Test
    func `a different run does not inherit reviewer keyboard focus`() throws {
        let run = failedRun()
        let host = ReviewTeamFocusTestHost(run: run)
        defer { host.close() }
        host.window.selectKeyView(following: host.editor)
        #expect(try host.focusMaskIsVisible(host.reviewer()))
        host.configure(run: failedRun(id: "replacement-run"))

        let reviewer = try host.reviewer()
        #expect(host.window.firstResponder !== reviewer)
        #expect(try !host.focusMaskIsVisible(reviewer))
    }
}

/// Hosts the real transcript widget and details view with the same SwiftUI sheet presentation
/// as ContentView. Keyboard events use the window responder chain; offscreen mouse events enter
/// the native row after claiming focus because XCTest cannot activate this window for a click.
@MainActor
private final class ReviewTeamFocusTestHost {
    let window: NSWindow
    let widget = AppKitTranscriptHostToolWidgetRowView()
    let editor = NSTextField(string: "Message")
    private let container = NSView()
    private let state = ReviewTeamFocusSheetState()
    private let previousEnhancedInterface: Any?
    private let enhancedInterface = "AXEnhancedUserInterface" as NSString

    var requestedReviewerID: String? { state.request?.reviewerID }

    init(run: ReviewTeamRun) {
        previousEnhancedInterface = NSApp.perform(
            NSSelectorFromString("accessibilityAttributeValue:"), with: enhancedInterface
        )?.takeUnretainedValue()
        _ = NSApp.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: enhancedInterface
        )
        window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 900, height: 900),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.autorecalculatesKeyViewLoop = false
        container.addSubview(widget)
        container.addSubview(editor)
        widget.translatesAutoresizingMaskIntoConstraints = true
        widget.frame = NSRect(x: 20, y: 200, width: 700, height: 600)
        editor.frame = NSRect(x: 20, y: 50, width: 600, height: 30)
        let content = ReviewTeamFocusSheetHost(container: container, widget: widget, state: state)
        window.contentViewController = NSHostingController(rootView: content)
        configure(run: run)
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.makeFirstResponder(editor)
    }

    func configure(run: ReviewTeamRun, fontSize: Int = 14) {
        var settings = AppSettings()
        settings.chatFontSize = fontSize
        widget.configure(.init(entry: HostToolWidgetEntry(
            id: "collective-review-run:\(run.id)", toolName: "Collective review", content: .collectiveReviewRun(run),
            isComplete: !run.phase.isWorking, isError: run.phase == .failed
        ), bubbleMaxWidth: 700, typography: TranscriptTypography(settings: settings)))
        widget.layoutSubtreeIfNeeded()
        let rows = reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: widget)
        let controls: [NSView] = [editor] + rows
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
    }

    func reviewer(at index: Int = 0) throws -> AppKitReviewTeamReviewerRowView {
        let rows = reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: widget)
        try #require(rows.indices.contains(index))
        return rows[index]
    }

    func click(_ view: AppKitReviewTeamReviewerRowView) throws {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        #expect(window.makeFirstResponder(view))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ))
            if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseUp(with: event) }
        }
    }

    func sendKey(_ code: UInt16, characters: String, flags: NSEvent.ModifierFlags = [], to target: NSWindow? = nil) throws {
        let target = target ?? window
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: target.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
        NSApp.sendEvent(event)
    }

    func focusMaskIsVisible(_ row: AppKitReviewTeamReviewerRowView) throws -> Bool {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(ceil(row.bounds.width)), pixelsHigh: Int(ceil(row.bounds.height)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(row.bounds)
        NSColor.black.setFill()
        row.drawFocusRingMask()
        NSGraphicsContext.restoreGraphicsState()
        return (bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.alphaComponent ?? 0) > 0.9
    }

    func pressAccessibilityButton(named name: String, in root: Any?) throws {
        let button = try #require(accessibilityButton(named: name, in: root))
        let selector = NSSelectorFromString("accessibilityPerformPress")
        try #require(button.responds(to: selector))
        // SwiftUI's virtual buttons expose the selector without protocol conformance.
        // Its Boolean return requires the declared ABI, not NSObject.perform's object return.
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let press = unsafeBitCast(button.method(for: selector), to: Press.self)
        #expect(press(button, selector))
    }

    private func accessibilityButton(named name: String, in element: Any?, depth: Int = 0) -> NSObject? {
        guard depth < 30, let node = element as? NSObject else { return nil }
        let labels = ["accessibilityLabel", "accessibilityTitle"].compactMap { name -> String? in
            let selector = NSSelectorFromString(name)
            return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
        }
        if labels.contains(name), node.responds(to: NSSelectorFromString("accessibilityPerformPress")) { return node }
        let selector = NSSelectorFromString("accessibilityChildren")
        let children = node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? [Any] : nil
        for child in children ?? [] {
            if let button = accessibilityButton(named: name, in: child, depth: depth + 1) { return button }
        }
        return nil
    }

    func waitUntil(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try #require(condition())
    }

    func close() {
        state.request = nil
        try? waitUntil { window.attachedSheet == nil }
        window.makeFirstResponder(nil)
        window.contentViewController = nil
        window.close()
        _ = NSApp.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: previousEnhancedInterface, with: enhancedInterface
        )
    }
}

@MainActor
@Observable
private final class ReviewTeamFocusSheetState {
    var request: ReviewTeamDetailsRequest?
}

private struct ReviewTeamFocusSheetHost: View {
    let container: NSView
    let widget: NSView
    @Bindable var state: ReviewTeamFocusSheetState

    var body: some View {
        ReviewTeamFocusContainer(container: container)
            .frame(width: 900, height: 900)
            .onReceive(NotificationCenter.default.publisher(for: .reviewTeamDetailsRequested)) { notification in
                guard let source = notification.object as? NSView, source.isDescendant(of: widget),
                      let run = notification.userInfo?["run"] as? ReviewTeamRun else { return }
                state.request = ReviewTeamDetailsRequest(run: run, reviewerID: notification.userInfo?["reviewerID"] as? String)
            }
            .sheet(item: $state.request) { request in
                ReviewTeamRunDetailsSheet(initialRun: request.run, initialReviewerID: request.reviewerID) {
                    state.request = nil
                }
            }
    }
}

private struct ReviewTeamFocusContainer: NSViewRepresentable {
    let container: NSView
    func makeNSView(context: Context) -> NSView { container }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
