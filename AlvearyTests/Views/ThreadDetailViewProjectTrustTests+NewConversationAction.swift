import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension ThreadDetailViewProjectTrustTests {
    func testHostedNewConversationToolbarTracksSetupAndCreatesOnce() async throws {
        let setup = MockHarnessSetupService()
        await setup.setTrustedProject("/tmp/alveary-project", isTrusted: true)
        let fixture = try ThreadDetailProjectTrustFixture(harnessSetup: setup)
        let host = try HostedNewConversationToolbar(fixtures: [fixture])
        do {
            try await host.requireRendered { host.buttonEnabled == nil }
            XCTAssertNil(host.action)

            fixture.thread.hasCompletedInitialSetup = true
            try fixture.context.save()
            try await host.requireRendered { host.buttonEnabled == true }
            try host.pressNewConversation()
            try await host.requireRendered { fixture.view.conversations.count == 2 }
            XCTAssertEqual(fixture.view.conversations.count, 2)
            XCTAssertNotEqual(
                fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID],
                fixture.conversation.persistentModelID
            )

            fixture.thread.hasCompletedInitialSetup = false
            try fixture.context.save()
            try await host.requireRendered { host.buttonEnabled == nil && host.action == nil }
        } catch {
            host.close()
            await awaitSnapshotHostTeardown(retaining: fixture.container)
            throw error
        }
        host.close()
        await awaitSnapshotHostTeardown(retaining: fixture.container)
    }

    func testHostedNewConversationToolbarReplacesAndClearsThreadAction() async throws {
        let setup = MockHarnessSetupService()
        await setup.setTrustedProject("/tmp/alveary-project", isTrusted: true)
        let first = try ThreadDetailProjectTrustFixture(hasCompletedInitialSetup: true, harnessSetup: setup)
        let second = try ThreadDetailProjectTrustFixture(hasCompletedInitialSetup: true, harnessSetup: setup)
        let host = try HostedNewConversationToolbar(fixtures: [first, second])
        do {
            try await host.requireRendered { host.buttonEnabled == true }
            let oldAction = try XCTUnwrap(host.action)
            first.appState.selectedSidebarItem = .thread(second.thread)
            try await host.requireRendered { host.action?.threadID == second.thread.persistentModelID && host.buttonEnabled == true }
            oldAction()
            try host.pressNewConversation()
            try await host.requireRendered { second.view.conversations.count == 2 }
            XCTAssertEqual(first.view.conversations.count, 1, "A retained action must not create in the old thread")

            first.appState.selectedSidebarItem = .skills
            try await host.requireRendered { host.action == nil && host.buttonEnabled == nil }
        } catch {
            host.close()
            await awaitSnapshotHostTeardown(retaining: [first.container, second.container])
            throw error
        }
        host.close()
        await awaitSnapshotHostTeardown(retaining: [first.container, second.container])
    }

    func testHostedNewConversationActionRequiresSetupAfterProjectTrust() async throws {
        var settings = AppSettings()
        settings.autoTrustProjects = false
        let fixture = try ThreadDetailProjectTrustFixture(settings: settings)
        let host = try HostedNewConversationToolbar(fixtures: [fixture])
        do {
            try await host.requireRendered { host.buttonEnabled == nil }
            XCTAssertNil(host.action)
            // Update the same service used by the mounted view, then remount to refresh its trust check.
            fixture.appState.selectedSidebarItem = .skills
            try await host.requireRendered { host.buttonEnabled == nil }
            await fixture.view.harnessSetup.trustProject(harnessId: "claude", workingDirectory: fixture.project.path)
            fixture.appState.selectedSidebarItem = .thread(fixture.thread)
            try await host.requireRendered { host.buttonEnabled == nil && host.action == nil }
            fixture.thread.hasCompletedInitialSetup = true
            try await host.requireRendered { host.buttonEnabled == true }
        } catch {
            host.close()
            await awaitSnapshotHostTeardown(retaining: fixture.container)
            throw error
        }
        host.close()
        await awaitSnapshotHostTeardown(retaining: fixture.container)
    }
}

/// Exercises the real thread publisher and header inside separate content/toolbar hosts.
/// A directly injected snapshot closure would bypass the propagation failure this covers.
@MainActor
private final class HostedNewConversationToolbar {
    var action: NewConversationAction?
    private var controller: NSHostingController<AnyView>?
    private var window: NSWindow?
    private let previousEnhancedInterface: Any
    private let enhancedInterface = "AXEnhancedUserInterface" as NSString

    init(fixtures: [ThreadDetailProjectTrustFixture]) throws {
        let application = NSApplication.shared
        previousEnhancedInterface = try XCTUnwrap(application.perform(
            NSSelectorFromString("accessibilityAttributeValue:"), with: enhancedInterface
        )?.takeUnretainedValue())
        _ = application.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: true as NSNumber, with: enhancedInterface
        )
        let first = try XCTUnwrap(fixtures.first)
        let root = NewConversationToolbarTestRoot(fixtures: fixtures, appState: first.appState) { [weak self] in
            self?.action = $0
        }
        let controller = NSHostingController(rootView: AnyView(root))
        let window = NSWindow(
            contentRect: NSRect(x: -3_000, y: -3_000, width: 900, height: 650),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        self.controller = controller
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    var buttonEnabled: Bool? {
        button?.value(forKey: "accessibilityEnabled") as? Bool
    }

    func requireRendered(file: StaticString = #filePath, line: UInt = #line, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            window?.layoutIfNeeded()
            window?.displayIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        let labels = window.map { accessibilityNodes(($0.contentView?.superview as NSObject?) ?? $0).compactMap { node -> String? in
            let selector = NSSelectorFromString("accessibilityLabel")
            return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? String : nil
        } } ?? []
        let diagnostic = "action=\(String(describing: action?.threadID)), toolbar=\(String(describing: window?.toolbar)), labels=\(labels)"
        _ = try XCTUnwrap(condition() ? true : nil, "Toolbar did not reach expected state: \(diagnostic)", file: file, line: line)
    }

    func pressNewConversation() throws {
        let button = try XCTUnwrap(button)
        XCTAssertEqual(buttonEnabled, true)
        let selector = NSSelectorFromString("accessibilityPerformPress")
        XCTAssertTrue(button.responds(to: selector))
        // SwiftUI's virtual button exposes this selector without NSAccessibilityProtocol conformance.
        // Invoke the documented Boolean ABI; NSObject.perform(_:) expects an object return instead.
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let press = unsafeBitCast(button.method(for: selector), to: Press.self)
        XCTAssertTrue(press(button, selector))
    }

    func close() {
        if let window, let controller {
            closeSnapshotWindow(window, controller: controller)
        }
        window = nil
        controller = nil
        action = nil
        _ = NSApplication.shared.perform(
            NSSelectorFromString("accessibilitySetValue:forAttribute:"), with: previousEnhancedInterface, with: enhancedInterface
        )
    }

    private var button: NSObject? {
        guard let window else { return nil }
        let roots: [NSObject] = [(window.contentView?.superview as NSObject?) ?? window] + (window.toolbar?.items.compactMap(\.view) ?? [])
        return roots.flatMap { accessibilityNodes($0) }.first {
            $0.responds(to: NSSelectorFromString("accessibilityLabel")) &&
                $0.perform(NSSelectorFromString("accessibilityLabel"))?.takeUnretainedValue() as? String == "New Conversation"
        }
    }

    private func accessibilityNodes(_ node: NSObject, depth: Int = 0) -> [NSObject] {
        guard depth < 30 else { return [] }
        let selector = NSSelectorFromString("accessibilityChildren")
        let children = node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() as? [NSObject] : nil
        let nativeChildren = (node as? NSView)?.subviews ?? []
        let descendants = (children ?? []) + nativeChildren.filter { child in !(children ?? []).contains { $0 === child } }
        return [node] + descendants.flatMap { accessibilityNodes($0, depth: depth + 1) }
    }
}

private struct NewConversationToolbarTestRoot: View {
    let fixtures: [ThreadDetailProjectTrustFixture]
    @Bindable var appState: AppState
    let onActionChange: (NewConversationAction?) -> Void
    @State private var action: NewConversationAction?

    private var selectedFixture: ThreadDetailProjectTrustFixture? {
        guard case .thread(let selected) = appState.selectedSidebarItem else { return nil }
        return fixtures.first { $0.thread.persistentModelID == selected.persistentModelID }
    }

    var body: some View {
        Group {
            if let fixture = selectedFixture {
                threadView(fixture)
                    .id(fixture.thread.persistentModelID)
                    .modelContainer(fixture.container)
                    .environment(\.modelContext, fixture.context)
            } else {
                Color.clear
            }
        }
        .onPreferenceChange(NewConversationActionPreferenceKey.self) {
            action = $0
            onActionChange($0)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let fixture = selectedFixture {
                    MainPaneToolbarHeaderItem(
                        presentation: MainPaneHeaderPresentation(selection: .thread(fixture.thread), modelContext: fixture.context),
                        voiceInputLifecycleController: fixture.view.voiceInputLifecycleController,
                        newConversationAction: action
                    )
                }
            }
        }
    }

    private func threadView(_ fixture: ThreadDetailProjectTrustFixture) -> ThreadDetailView {
        var view = fixture.view
        view.appState = appState
        return view
    }
}
