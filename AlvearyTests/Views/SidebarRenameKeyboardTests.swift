import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

/// Hosts the real List beside an editor: the List's native focus proxy is outside its scroll
/// view, and a sidebar-only host would not prove that another pane retains keyboard ownership.
@MainActor
final class SidebarRenameKeyboardTests: XCTestCase {
    private typealias Host = (window: NSWindow, controller: NSHostingController<AnyView>)

    func testReturnStartsFocusedRenameAcrossSidebarPlacements() async throws {
        for placement in Placement.allCases {
            let fixture = try SidebarTestFixture()
            let thread = try makeThread(placement: placement, fixture: fixture)
            let appState = AppState()
            try await withHost(fixture: fixture, appState: appState) { host in
                appState.selectedSidebarItem = .thread(thread)
                try await waitForSidebarFocus(in: host, context: "\(placement)")
                let monitor = try XCTUnwrap(descendants(in: host.controller.view, of: SidebarRenameKeyMonitorView.self).first)
                let onRename = try XCTUnwrap(monitor.onRename)
                var renameAccepted: Bool?
                monitor.onRename = {
                    let accepted = onRename()
                    renameAccepted = accepted
                    return accepted
                }
                try sendKey(window: host.window)
                monitor.onRename = onRename
                XCTAssertEqual(renameAccepted, true, "\(placement): native Return did not start rename")
                try await waitForRenameEditor(in: host, context: "\(placement)")
                let field = try XCTUnwrap(renameField(in: host))
                let editor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
                XCTAssertTrue(field.currentEditor() === editor)
                XCTAssertEqual(editor.string, thread.displayName())
                XCTAssertFalse(thread.hasCustomName)
            }
        }
    }

    func testKeypadEnterWithCapsLockStartsRename() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeThread(fixture: fixture)
        let appState = AppState()
        try await withHost(fixture: fixture, appState: appState) { host in
            appState.selectedSidebarItem = .thread(thread)
            try await waitForSidebarFocus(in: host)
            try sendKey(76, characters: "\u{3}", flags: [.capsLock, .numericPad], window: host.window)
            try await waitForRenameEditor(in: host)
            XCTAssertEqual(renameField(in: host)?.stringValue, thread.displayName())
            XCTAssertTrue(host.window.firstResponder is NSTextView)
        }
    }

    func testReturnRenamesProjectChildWithoutThreadOrderAnimation() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeThread(placement: .project, fixture: fixture)
        thread.modifiedAt = .now
        // More than 200 expanded children keeps the animation nil before and during rename,
        // as Reduce Motion does. Older siblings keep the selected target visible at the top.
        for index in 0..<200 {
            fixture.context.insert(AgentThread(
                name: "Older task \(index)", modifiedAt: .distantPast, mode: .task, project: thread.project
            ))
        }
        try fixture.context.save()
        let appState = AppState()
        try await withHost(fixture: fixture, appState: appState) { host in
            appState.selectedSidebarItem = .thread(thread)
            for _ in 0..<2 {
                try await waitForSidebarFocus(in: host)
                try sendKey(window: host.window)
                try await waitForRenameEditor(in: host)
                let field = try XCTUnwrap(renameField(in: host))
                let editor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
                XCTAssertTrue(field.currentEditor() === editor)
                XCTAssertEqual(editor.string, thread.displayName())
                try sendKey(53, characters: "\u{1b}", window: host.window, throughApplication: false)
                try await waitForSidebarFocus(in: host)
                XCTAssertNil(renameField(in: host))
                XCTAssertFalse(thread.hasCustomName)
            }
        }
    }

    func testModifiedReturnDoesNotFallThroughToSwiftUIRename() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeThread(fixture: fixture)
        let appState = AppState()
        try await withHost(fixture: fixture, appState: appState) { host in
            appState.selectedSidebarItem = .thread(thread)
            try await waitForSidebarFocus(in: host)
            let sidebarResponder = try XCTUnwrap(host.window.firstResponder)
            for flags: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
                XCTAssertTrue(host.window.makeFirstResponder(sidebarResponder))
                try sendKey(flags: flags, window: host.window)
                await settle(host.window)
                XCTAssertNil(renameField(in: host))
            }
        }
    }

    func testCommitCancelAndSubsequentKeyboardNavigation() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeThread(fixture: fixture)
        let appState = AppState()
        try await withHost(fixture: fixture, appState: appState) { host in
            appState.selectedSidebarItem = .thread(thread)
            try await waitForSidebarFocus(in: host)
            try sendKey(window: host.window)
            try await waitForRenameEditor(in: host)
            let editor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
            editor.selectAll(nil)
            editor.insertText("Renamed task", replacementRange: editor.selectedRange())
            await settle(host.window)
            try sendKey(window: host.window, throughApplication: false)
            try await waitForSidebarFocus(in: host)
            XCTAssertEqual(thread.name, "Renamed task")
            XCTAssertTrue(thread.hasCustomName)
            XCTAssertNil(renameField(in: host))

            try sendKey(window: host.window)
            try await waitForRenameEditor(in: host)
            let nextEditor = try XCTUnwrap(host.window.firstResponder as? NSTextView)
            nextEditor.selectAll(nil)
            nextEditor.insertText("Cancel this change", replacementRange: nextEditor.selectedRange())
            await settle(host.window)
            try sendKey(53, characters: "\u{1b}", window: host.window, throughApplication: false)
            try await waitForSidebarFocus(in: host)
            XCTAssertEqual(thread.name, "Renamed task")
            XCTAssertNil(renameField(in: host))
            try sendKey(126, characters: "\u{f700}", window: host.window, throughApplication: false)
            await settle(host.window)
            XCTAssertNotEqual(appState.selectedSidebarItem, .thread(thread))
        }
    }

    func testNeighboringEditorKeepsReturnAndRenameBlurKeepsItsFocus() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeThread(fixture: fixture)
        let appState = AppState()
        try await withHost(fixture: fixture, appState: appState) { host in
            appState.selectedSidebarItem = .thread(thread)
            try await waitForSidebarFocus(in: host)
            try sendKey(window: host.window)
            try await waitForRenameEditor(in: host)
            XCTAssertNotNil(renameField(in: host))
            let neighbor = try XCTUnwrap(descendants(in: host.controller.view, of: NSTextField.self)
                .first { $0.placeholderString == "Composer" })
            XCTAssertTrue(host.window.makeFirstResponder(neighbor))
            await settle(host.window)
            XCTAssertNil(renameField(in: host))
            XCTAssertFalse(thread.hasCustomName, "An unchanged blur must not pin an automatically generated title")
            let editor = try XCTUnwrap(neighbor.currentEditor())
            XCTAssertTrue(host.window.firstResponder === editor)
            try sendKey(window: host.window)
            await settle(host.window)
            XCTAssertNil(renameField(in: host))
        }
    }

    func testNewSectionEditorOwnsReturnAndNonTaskSelectionCannotRename() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try makeThread(fixture: fixture)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(thread)
        try await withHost(fixture: fixture, appState: appState, isCreatingSection: true) { host in
            try sendKey(window: host.window)
            await settle(host.window)
            XCTAssertNil(renameField(in: host))
            appState.selectedSidebarItem = .skills
            await settle(host.window)
            try sendKey(window: host.window)
            await settle(host.window)
            XCTAssertNil(renameField(in: host))
        }
    }

    private func makeThread(placement: Placement = .task, fixture: SidebarTestFixture) throws -> AgentThread {
        let thread = AgentThread(name: "Rename this task", mode: .task)
        switch placement {
        case .task:
            break
        case .project:
            let project = Project(path: "/tmp/sidebar-rename-project", name: "Project")
            fixture.context.insert(project)
            thread.project = project
        case .pinned:
            thread.isPinned = true
            thread.pinnedSortOrder = 0
        case .customSection:
            let section = SidebarSection(kind: .custom, name: "Research", sortOrder: 3)
            fixture.context.insert(section)
            thread.customSection = section
        }
        fixture.context.insert(thread)
        try fixture.context.save()
        return thread
    }

    private func withHost(
        fixture: SidebarTestFixture,
        appState: AppState,
        isCreatingSection: Bool = false,
        perform: (Host) async throws -> Void
    ) async throws {
        // Initialize persisted ordering before hosting; onAppear must not rewrite project and
        // section models while this keyboard test is driving SwiftUI's mounted rows.
        try fixture.viewModel.ensureSidebarOrderingInitialized()
        let expandedProjects = Set(try fixture.context.fetch(FetchDescriptor<Project>()).map(\.id))
        let controller = NSHostingController(rootView: AnyView(
            HStack(spacing: 0) {
                SidebarView(
                    viewModel: fixture.viewModel, appState: appState,
                    initialExpandedProjects: expandedProjects,
                    initialIsCreatingSection: isCreatingSection
                )
                    .frame(width: 360, height: 720)
                TextField("Composer", text: .constant(""))
                    .frame(width: 280, height: 720)
            }
            .environment(\.modelContext, fixture.context)
            .modelContainer(fixture.container)
        ))
        let frame = NSRect(x: 0, y: 0, width: 640, height: 720)
        controller.view.frame = frame
        let window = SidebarRenameTestWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setFrameOrigin(NSPoint(x: -3_000, y: -3_000))
        window.orderFront(nil)
        controller.view.layoutSubtreeIfNeeded()
        do {
            await settle(window)
            try await perform((window, controller))
        } catch {
            closeSnapshotWindow(window, controller: controller)
            await awaitSnapshotHostTeardown(retaining: fixture)
            throw error
        }
        closeSnapshotWindow(window, controller: controller)
        await awaitSnapshotHostTeardown(retaining: fixture)
    }

    /// Selection, native List layout, and SwiftUI focus settle independently on hosted runners.
    /// Observe readiness without forcing a responder or retrying the Return event under test.
    private func waitForSidebarFocus(in host: Host, context: String = "sidebar") async throws {
        var focusDescription = "no native focus view"
        do {
            try await waitUntil("\(context): sidebar focus") {
                host.window.layoutIfNeeded()
                host.window.displayIfNeeded()
                guard self.renameField(in: host) == nil,
                      let monitor = self.descendants(in: host.controller.view, of: SidebarRenameKeyMonitorView.self).first,
                      monitor.window === host.window,
                      let responder = host.window.firstResponder as? NSView else {
                    return false
                }
                let focusView = (responder as? NSTableView)?.enclosingScrollView ?? responder
                let sidebarRect = monitor.convert(monitor.bounds, to: nil)
                let focusRect = focusView.convert(focusView.bounds, to: nil)
                focusDescription = "\(type(of: responder)), focus \(focusRect), sidebar \(sidebarRect)"
                return !(responder is NSText) && !responder.isHiddenOrHasHiddenAncestor
                    && !monitor.isHiddenOrHasHiddenAncestor && !sidebarRect.isEmpty && !focusRect.isEmpty
                    && abs(sidebarRect.minX - focusRect.minX) <= 1 && abs(sidebarRect.minY - focusRect.minY) <= 1
                    && abs(sidebarRect.width - focusRect.width) <= 1 && abs(sidebarRect.height - focusRect.height) <= 1
            }
        } catch {
            throw WaitTimeoutError(description: "\(context): sidebar did not acquire native focus (\(focusDescription))")
        }
    }

    private func waitForRenameEditor(in host: Host, context: String = "sidebar") async throws {
        var observedField = false
        do {
            try await waitUntil("\(context): rename editor focus") {
                host.window.layoutIfNeeded()
                host.window.displayIfNeeded()
                guard let field = self.renameField(in: host) else { return false }
                observedField = true
                guard let editor = field.currentEditor() as? NSTextView else { return false }
                return host.window.firstResponder === editor
            }
        } catch {
            let responder = host.window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            let changes = (host.window as? SidebarRenameTestWindow)?.responderChanges.suffix(8).joined(separator: ", ") ?? ""
            throw WaitTimeoutError(description:
                "\(context): rename editor focus timed out; field observed=\(observedField), "
                + "field mounted=\(renameField(in: host) != nil), responder=\(responder), changes=[\(changes)]"
            )
        }
    }

    private func settle(_ window: NSWindow) async {
        for _ in 0..<10 {
            window.layoutIfNeeded()
            window.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func sendKey(
        _ keyCode: UInt16 = 36,
        characters: String = "\r",
        flags: NSEvent.ModifierFlags = [],
        window: NSWindow,
        throughApplication: Bool = true
    ) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ))
        if throughApplication {
            // Entry and pass-through coverage must exercise the real local-monitor chain.
            NSApp.sendEvent(event)
        } else {
            // The existing editor/navigation responder is tested in its own window: XCTest
            // does not register this offscreen host as NSApp's actual key window.
            window.sendEvent(event)
        }
    }

    private func renameField(in host: Host) -> NSTextField? {
        descendants(in: host.controller.view, of: NSTextField.self).first { $0.placeholderString == "Thread name" }
    }

    private func descendants<View: NSView>(in root: NSView, of type: View.Type) -> [View] {
        (root as? View).map { [$0] } ?? root.subviews.flatMap { descendants(in: $0, of: type) }
    }

    private enum Placement: CaseIterable {
        case task, project, pinned, customSection
    }
}

/// Borderless keyboard hosts explicitly opt into AppKit's key-window eligibility.
private final class SidebarRenameTestWindow: NSWindow {
    private(set) var responderChanges: [String] = []

    override var canBecomeKey: Bool { true }
    // XCTest does not register the offscreen host as NSApp's actual key window.
    override var isKeyWindow: Bool { true }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        let name = responder.map { String(describing: type(of: $0)) } ?? "nil"
        responderChanges.append("\(name): \(accepted)")
        return accepted
    }
}
