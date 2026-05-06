@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testComposerPanelUsesNativeBodyWhenConfigured() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 140))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.red.frame(height: 44)),
                nativeBodyConfiguration: makeComposerBodyConfiguration(text: "Review @Alveary/Views/Input/AppKitChatComposerBodyView.swift"),
                actionRowConfiguration: makeActionRowConfiguration(),
                showsTopDivider: false,
                hasTopContent: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14,
                    bottomPadding: 16
                )
            )
        )

        panel.layoutSubtreeIfNeeded()

        let nativeBody = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerBodyView } as? AppKitChatComposerBodyView)
        let contentHost = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatSurfaceHostingView })
        XCTAssertFalse(nativeBody.isHidden)
        XCTAssertTrue(contentHost.isHidden)
        XCTAssertEqual(nativeBody.frame, NSRect(x: 20, y: 0, width: 279, height: 84))
        XCTAssertEqual(nativeBody.editorView.frame, NSRect(x: 0, y: 16, width: 279, height: 68))
        XCTAssertEqual(nativeBody.editorView.textViewForTesting.string, "Review @Alveary/Views/Input/AppKitChatComposerBodyView.swift")
    }

    func testComposerBodyRefreshesInlineHintWhenSkillArgumentHintsArrive() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let text = "/review-github-pr"
        body.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        body.isComposerFirstResponder = true
        body.configure(makeComposerBodyConfiguration(text: text))

        XCTAssertNil(body.editorView.textViewForTesting.inlineHint)

        body.skillArgumentHints = ["review-github-pr": "[PR URL]"]
        body.refreshEditorConfiguration()

        XCTAssertEqual(body.editorView.textViewForTesting.inlineHint, AppTextEditorInlineHint(text: " [PR URL]"))
    }

    func testComposerBodyRefreshUsesLatestLocalTextBeforeParentReconfigure() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "/"))

        let localText = "/review-github-pr"
        body.isComposerFirstResponder = true
        body.selectedRange = NSRange(location: (localText as NSString).length, length: 0)
        body.handleTextChange(localText)
        body.skillArgumentHints = ["review-github-pr": "[PR URL]"]

        body.refreshEditorConfiguration()

        XCTAssertEqual(body.editorView.textViewForTesting.string, localText)
        XCTAssertEqual(body.editorView.textViewForTesting.inlineHint, AppTextEditorInlineHint(text: " [PR URL]"))
    }

    func testComposerBodySubmitUsesLatestLocalTextBeforeParentReconfigure() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        var submitCount = 0
        body.configure(makeComposerBodyConfiguration(text: "", onSubmit: {
            submitCount += 1
        }))

        body.handleTextChange("Draft")
        body.performSubmit(configuration: try XCTUnwrap(body.configuration))

        XCTAssertEqual(submitCount, 1)
    }

    func testComposerBodyAutocompleteSelectionRefreshesEditorBeforeParentReconfigure() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "Review @Cha"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<11,
            query: "Cha",
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: "ChatView.swift",
                    title: "ChatView.swift",
                    subtitle: nil,
                    trailingText: nil,
                    replacementText: "@ChatView.swift",
                    symbolName: "doc.text"
                )
            ],
            isLoading: false
        )

        body.applyAutocompleteSuggestion(try XCTUnwrap(body.activeAutocomplete?.suggestions.first))

        XCTAssertEqual(body.editorView.textViewForTesting.string, "Review @ChatView.swift ")
        XCTAssertEqual(body.editorView.textViewForTesting.selectedRange(), NSRange(location: 23, length: 0))
    }

    func testComposerBodyDoesNotHitTestSurfaceHoistedAutocompletePopupAboveBounds() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "Review @"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: [
                makeComposerBodySuggestion(id: "first", title: "First.swift", replacementText: "@First.swift")
            ],
            isLoading: false
        )
        body.configureAutocompletePopup()

        let popupPointAboveBody = NSPoint(x: 48, y: body.autocompletePopupFrame.minY + 24)

        XCTAssertNil(body.hitTest(popupPointAboveBody))
    }

    func testComposerBodyAutocompleteArrowKeysMoveHighlightedSuggestion() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "Review @"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: [
                makeComposerBodySuggestion(id: "first", title: "First.swift", replacementText: "@First.swift"),
                makeComposerBodySuggestion(id: "second", title: "Second.swift", replacementText: "@Second.swift")
            ],
            highlightedIndex: 0,
            isLoading: false
        )

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .downArrow, modifiers: [])), .handled)
        XCTAssertEqual(body.activeAutocomplete?.highlightedIndex, 1)

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .upArrow, modifiers: [])), .handled)
        XCTAssertEqual(body.activeAutocomplete?.highlightedIndex, 0)
    }

    func testComposerBodyTabAppliesHighlightedAutocompleteSuggestion() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "Review @Cha"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<11,
            query: "Cha",
            suggestions: [
                makeComposerBodySuggestion(id: "ChatView.swift", title: "ChatView.swift", replacementText: "@ChatView.swift")
            ],
            isLoading: false
        )

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .tab, modifiers: [])), .handled)

        XCTAssertEqual(body.editorView.textViewForTesting.string, "Review @ChatView.swift ")
        XCTAssertNil(body.activeAutocomplete)
    }

    func testComposerBodyReturnSubmitsExactSkillAutocompleteMatch() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        var submitCount = 0
        body.configure(makeComposerBodyConfiguration(text: "/review-github-pr", onSubmit: {
            submitCount += 1
        }))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .skill,
            replacementOffsets: 0..<17,
            query: "review-github-pr",
            suggestions: [
                makeComposerBodySuggestion(
                    id: "review-github-pr",
                    title: "review-github-pr",
                    replacementText: "/review-github-pr",
                    symbolName: "shippingbox"
                )
            ],
            isLoading: false
        )

        XCTAssertEqual(body.handleKeyPress(AppTextEditorKeyPress(key: .return, modifiers: [])), .handled)

        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(body.editorView.textViewForTesting.string, "/review-github-pr")
    }

    func testComposerBodyDismissesAutocompleteWhenProjectTrustBlocksEditor() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "Review @"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: [
                makeComposerBodySuggestion(id: "first", title: "First.swift", replacementText: "@First.swift")
            ],
            isLoading: false
        )
        body.configureAutocompletePopup()

        body.configure(makeComposerBodyConfiguration(text: "Review @", isProjectTrustBlocked: true))

        XCTAssertNil(body.activeAutocomplete)
        XCTAssertTrue(body.autocompletePopupView.isHidden)
        XCTAssertTrue(body.editorView.configuration.isDisabled)
        XCTAssertTrue(body.editorView.configuration.showsDisabledCursor)
    }

    func testSurfaceHoistsNativeAutocompletePopupAboveComposerPanel() throws {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let content = AutocompleteFixedHeightView(height: 100)
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        panel.configure(
            AppKitChatComposerPanelConfiguration(
                content: AnyView(Color.clear.frame(height: 44)),
                nativeBodyConfiguration: makeComposerBodyConfiguration(text: "Review @"),
                showsTopDivider: true,
                hasTopContent: false,
                layout: AppKitChatComposerPanelView.Layout(
                    horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 21),
                    topContentSpacing: 8,
                    actionRowSpacing: 14
                )
            )
        )
        surface.configure(contentView: content, composerView: panel)
        surface.layoutSubtreeIfNeeded()

        let body = try XCTUnwrap(panel.subviews.first { $0 is AppKitChatComposerBodyView } as? AppKitChatComposerBodyView)
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: [
                makeComposerBodySuggestion(id: "first", title: "First.swift", replacementText: "@First.swift")
            ],
            isLoading: false
        )
        body.configureAutocompletePopup()
        surface.layoutSubtreeIfNeeded()

        let popup = body.autocompletePopupView
        XCTAssertTrue(popup.superview === surface)
        XCTAssertEqual(popup.frame, try XCTUnwrap(body.autocompletePopupFrame(in: surface)))
        XCTAssertTrue(surface.subviews.contains(popup))
        XCTAssertFalse(surface.subviews.last === panel)
    }

    func testComposerBodyForwardsFocusRequestTokenToEditor() async {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let requestToken = UUID()
        let consumedExpectation = expectation(description: "Focus request consumed")
        var consumedToken: UUID?
        body.configure(
            makeComposerBodyConfiguration(
                text: "Review",
                requestFirstResponder: requestToken,
                onFocusRequestConsumed: { token in
                    consumedToken = token
                    consumedExpectation.fulfill()
                }
            )
        )

        await fulfillment(of: [consumedExpectation], timeout: 1)

        XCTAssertEqual(body.editorView.configuration.requestFirstResponder, requestToken)
        XCTAssertEqual(consumedToken, requestToken)
    }

    func testComposerBodyDropRefreshesEditorBeforeParentReconfigure() throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let configuration = makeComposerBodyConfiguration(text: "Review")
        body.configure(configuration)

        let handled = body.handleDroppedFiles(
            [URL(fileURLWithPath: "/tmp/alveary/ChatView.swift")],
            configuration: try XCTUnwrap(body.configuration)
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(body.editorView.textViewForTesting.string, "Review @ChatView.swift ")
        XCTAssertEqual(body.editorView.textViewForTesting.selectedRange(), NSRange(location: 23, length: 0))
    }

    func testComposerBodyNotifiesPanelWhenMeasuredHeightChanges() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        var invalidationCount = 0
        body.onPreferredSizeInvalidated = {
            invalidationCount += 1
        }

        body.handleMeasuredHeightChange(120)

        XCTAssertEqual(body.measuredEditorHeight, 120)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testComposerBodyResetsSkillArgumentHintsWhenWorkingDirectoryChanges() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "/review-github-pr"))
        body.skillArgumentHints = ["review-github-pr": "[PR URL]"]
        body.hasLoadedSkillArgumentHints = true

        body.configure(makeComposerBodyConfiguration(text: "/review-github-pr", workingDirectory: "/tmp/other"))

        XCTAssertTrue(body.skillArgumentHints.isEmpty)
        XCTAssertFalse(body.hasLoadedSkillArgumentHints)
    }

    func testComposerBodyIgnoresCancelledSkillAutocompleteHintLoad() async throws {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        let gate = SkillLoadGate()
        let configuration = makeComposerBodyConfiguration(
            text: "/review-github-pr",
            loadSkillCompletions: {
                await gate.load()
            }
        )
        let autocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .skill,
            replacementOffsets: 0..<17,
            query: "review-github-pr",
            isLoading: true
        )
        body.configure(configuration)
        body.activeAutocomplete = autocomplete

        body.loadAutocompleteSource(for: autocomplete, configuration: configuration)
        let loadTask = try XCTUnwrap(body.loadTask)
        await gate.waitForLoadRequest()

        body.dismissAutocomplete()
        await gate.complete([
            makeComposerBodySkill(id: "review-github-pr", argumentHint: "[PR URL]")
        ])
        await loadTask.value

        XCTAssertTrue(body.skillArgumentHints.isEmpty)
        XCTAssertFalse(body.hasLoadedSkillArgumentHints)
    }

    func testComposerBodyClearsAsyncTaskHandlesWhenDetached() {
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.loadTask = Task {}
        body.filterTask = Task {}
        body.skillHintLoadTask = Task {}
        body.stopConfirmationResetTask = Task {}

        body.cancelAsyncTasks()

        XCTAssertNil(body.loadTask)
        XCTAssertNil(body.filterTask)
        XCTAssertNil(body.skillHintLoadTask)
        XCTAssertNil(body.stopConfirmationResetTask)
    }

    func testSurfaceDismissesNativeAutocompletePopupOnOutsideMouseDown() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 320, height: 260))
        let content = AutocompleteFixedHeightView(height: 120)
        let body = AppKitChatComposerBodyView(frame: NSRect(x: 0, y: 0, width: 320, height: 84))
        body.configure(makeComposerBodyConfiguration(text: "Review @"))
        body.activeAutocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .file,
            replacementOffsets: 7..<8,
            query: "",
            suggestions: [
                makeComposerBodySuggestion(id: "first", title: "First.swift", replacementText: "@First.swift")
            ],
            highlightedIndex: 0,
            isLoading: false
        )
        body.configureAutocompletePopup()
        surface.configure(contentView: content, composerView: body)
        surface.layoutSubtreeIfNeeded()

        XCTAssertNotNil(body.activeAutocomplete)

        let outsidePoint = NSPoint(x: 12, y: 12)
        surface.mouseDown(with: Self.mouseEvent(type: .leftMouseDown, location: outsidePoint))

        XCTAssertNil(body.activeAutocomplete)
    }

}

@MainActor
private func makeComposerBodyConfiguration(
    text: String,
    workingDirectory: String = "/tmp/alveary",
    isProjectTrustBlocked: Bool = false,
    requestFirstResponder: UUID? = nil,
    loadSkillCompletions: @escaping @Sendable () async -> [Skill] = { [] },
    onSubmit: @escaping () -> Void = {},
    onFocusRequestConsumed: @escaping (UUID?) -> Void = { _ in }
) -> AppKitChatComposerBodyConfiguration {
    AppKitChatComposerBodyConfiguration(
        text: text,
        mode: .idle,
        defaultEnterBehavior: .queue,
        isStopConfirmationArmed: false,
        supportsMidTurnSteering: true,
        isProjectTrustBlocked: isProjectTrustBlocked,
        isHandoffSteeringPromptActive: false,
        isHandoffOutputPromptActive: false,
        handoffSteeringCountdown: nil,
        sendCountdown: nil,
        hasQueuedMessages: false,
        hasTopContent: false,
        workingDirectory: workingDirectory,
        requestFirstResponder: requestFirstResponder,
        colorScheme: .dark,
        loadFileCompletions: { [] },
        loadSkillCompletions: loadSkillCompletions,
        onTextChange: { _ in },
        onSubmit: onSubmit,
        onSteer: {},
        onStop: {},
        onStopConfirmationChange: { _ in },
        onFocusRequestConsumed: onFocusRequestConsumed
    )
}

private func makeComposerBodySkill(id: String, argumentHint: String?) -> Skill {
    Skill(
        id: id,
        name: id,
        description: id,
        argumentHint: argumentHint,
        version: nil,
        source: .local,
        isInstalled: true,
        syncedAgentIDs: [],
        owner: nil,
        repo: nil,
        sourceUrl: nil,
        installs: nil
    )
}

private func makeComposerBodySuggestion(
    id: String,
    title: String,
    replacementText: String,
    symbolName: String = "doc.text"
) -> ComposerAutocompleteSuggestion {
    ComposerAutocompleteSuggestion(
        id: id,
        title: title,
        subtitle: nil,
        trailingText: nil,
        replacementText: replacementText,
        symbolName: symbolName
    )
}

private actor SkillLoadGate {
    private var loadContinuation: CheckedContinuation<[Skill], Never>?
    private var requestContinuation: CheckedContinuation<Void, Never>?

    func load() async -> [Skill] {
        await withCheckedContinuation { continuation in
            loadContinuation = continuation
            requestContinuation?.resume()
            requestContinuation = nil
        }
    }

    func waitForLoadRequest() async {
        if loadContinuation != nil {
            return
        }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func complete(_ skills: [Skill]) {
        loadContinuation?.resume(returning: skills)
        loadContinuation = nil
    }
}
