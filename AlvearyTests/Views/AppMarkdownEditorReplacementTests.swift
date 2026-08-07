import AppKit
import BlockInputKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

/// `AppMarkdownDraft` has two replacement paths, and which one a host picks is
/// what decides whether the mounted editor survives. Reset took the caret-keeping
/// one, so the leftover caret scrolled the restored document under its top inset
/// and clipped the first block against the editor chrome.
@MainActor
final class AppMarkdownEditorReplacementTests: XCTestCase {
    /// A wholesale swap must rebuild the editor. A caret left over from the old
    /// document otherwise scrolls the new one under its top inset, which is how
    /// the Settings sheet's Reset clipped its first block.
    func testResetContentRebuildsTheEditor() async throws {
        let draft = AppMarkdownDraft(
            markdown: "An edited prompt.",
            referenceMarkdown: AppSettings.defaultPullRequestReviewPrompt
        )
        let host = mountSheet(draft: draft)
        defer { host.tearDown() }

        let original = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))
        await host.settle()

        // What the Reset button does.
        draft.resetContent(to: AppSettings.defaultPullRequestReviewPrompt)
        await host.settle()

        XCTAssertTrue(draft.matchesReference)
        let rebuilt = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))
        XCTAssertFalse(
            rebuilt === original,
            "Reset reused the mounted editor, so it keeps the old document's scroll position"
        )
    }

    /// The mid-edit path — an attachment link spliced into a comment being typed —
    /// must keep the same editor so the caret survives.
    func testReplaceTextKeepsTheMountedEditor() async throws {
        let draft = AppMarkdownDraft(markdown: "Typed comment")
        let host = mountEditor(draft: draft)
        defer { host.tearDown() }

        let original = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))
        await host.settle()

        draft.replaceText("Typed comment\n\n![shot](https://example.com/a.png)")
        await host.settle()

        let current = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))
        XCTAssertTrue(current === original, "A mid-edit splice rebuilt the editor and dropped the caret")
    }

    /// Reopening the proposal pane for a newer proposal replaces the bound draft
    /// under a still-mounted editor, so `onAppear` never runs again. The editor
    /// must follow, or it renders the previous proposal's instructions and writes
    /// them back over the new ones on submit.
    func testTheScheduledEditorFollowsAnExternallyReplacedPrompt() async throws {
        let viewModel = try makeScheduledTasksViewModel()
        var draft = viewModel.makeNewDraft()
        draft.prompt = "Summarize yesterday's commits."
        let box = ScheduledTaskEditorDraftBox(draft: draft)

        let host = mount(
            ScheduledTaskEditorHarness(box: box, viewModel: viewModel),
            size: NSRect(x: 0, y: 0, width: 640, height: 760)
        )
        defer { host.tearDown() }
        await host.settle()

        box.draft.prompt = "Summarize open pull requests instead."
        await host.settle()

        let editor = try XCTUnwrap(Self.firstBlockInputView(in: host.hosting))
        XCTAssertEqual(editor.document.markdown, "Summarize open pull requests instead.")
    }

    /// Mirrors how `ScheduledTaskEditorPane` hands the content a binding whose
    /// value the view model can replace underneath it.
    private struct ScheduledTaskEditorHarness: View {
        let box: ScheduledTaskEditorDraftBox
        let viewModel: ScheduledTasksViewModel

        var body: some View {
            ScheduledTaskEditorContent(
                viewModel: viewModel,
                draft: Binding(get: { box.draft }, set: { box.draft = $0 }),
                title: "Review Scheduled Task Proposal",
                subtitle: nil,
                submitTitle: "Confirm and create",
                errorMessage: nil,
                isSubmitting: false,
                surface: .pane,
                onDismissError: {},
                onSubmit: {},
                onClose: {}
            )
        }
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

    private func mountSheet(draft: AppMarkdownDraft) -> Host {
        mount(
            SettingsPromptEditorSheet(
                title: "Agentic review instructions",
                draft: draft,
                defaultPrompt: AppSettings.defaultPullRequestReviewPrompt,
                placeholder: "Placeholder",
                onCancel: {},
                onSave: {}
            ),
            size: NSRect(x: 0, y: 0, width: 720, height: 620)
        )
    }

    private func mountEditor(draft: AppMarkdownDraft) -> Host {
        mount(
            AppMarkdownEditor(
                draft: draft,
                placeholder: "Placeholder",
                sizing: .fillsAvailableHeight
            )
            .padding(12),
            size: NSRect(x: 0, y: 0, width: 620, height: 360)
        )
    }

    private func mount(_ view: some View, size: NSRect) -> Host {
        let hosting = NSHostingView(rootView: AnyView(view))
        hosting.frame = size
        let window = NSWindow(contentRect: size, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return Host(window: window, hosting: hosting)
    }

    private func makeScheduledTasksViewModel() throws -> ScheduledTasksViewModel {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let notificationCenter = NotificationCenter()
        return ScheduledTasksViewModel(
            modelContext: context,
            mutationService: ScheduledTaskMutationService(
                modelContext: context,
                notificationCenter: notificationCenter
            ),
            settingsService: InMemorySettingsService(),
            notificationCenter: notificationCenter,
            runNow: { _ in true },
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    private static func firstBlockInputView(in view: NSView) -> BlockInputView? {
        if let match = view as? BlockInputView {
            return match
        }
        return view.subviews.lazy.compactMap { firstBlockInputView(in: $0) }.first
    }
}

/// Stands in for the pane session a newer proposal is swapped into. Not nested in
/// the suite because `@Observable` cannot expand inside a `private` scope.
@MainActor
@Observable
final class ScheduledTaskEditorDraftBox {
    var draft: ScheduledTaskEditorDraft

    init(draft: ScheduledTaskEditorDraft) {
        self.draft = draft
    }
}
