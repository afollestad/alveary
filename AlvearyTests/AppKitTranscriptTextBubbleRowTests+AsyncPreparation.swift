@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    func testAsyncMarkdownPreparationAcceptsMatchingLayoutInputs() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Async prepared markdown \(UUID().uuidString) with `code`."
        let loader = ControlledAsyncMarkdownLoader()
        defer { loader.finishAllRequests() }
        row.asyncDocumentLoaderForTesting = loader.load(markdown:context:)
        row.hydratesMarkdownImmediately = false
        let configuration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "async-row",
            role: .assistant,
            markdown: markdown,
            bubbleMaxWidth: 360
        )
        row.configure(configuration)
        let context = row.preparedMeasurementContext(for: 320, configuration: configuration)
        row.scheduleAsyncMarkdownPreparation(for: context)
        try await loader.waitForRequestCount(1)
        let pendingKey = context.key

        loader.finishRequest(at: 0)
        await row.waitForAcceptedAsyncKey(pendingKey)

        XCTAssertEqual(row.acceptedAsyncKeyForTesting, pendingKey)
        XCTAssertEqual(row.acceptedAsyncKeyForTesting?.markdown, markdown)
    }

    func testAsyncMarkdownPreparationRejectsStaleContentResults() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let oldMarkdown = "Old async markdown \(UUID().uuidString)"
        let newMarkdown = "New async markdown \(UUID().uuidString)"
        let loader = ControlledAsyncMarkdownLoader()
        defer { loader.finishAllRequests() }
        row.asyncDocumentLoaderForTesting = loader.load(markdown:context:)
        row.hydratesMarkdownImmediately = false
        let oldConfiguration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "async-row",
            role: .assistant,
            markdown: oldMarkdown,
            bubbleMaxWidth: 360
        )
        let newConfiguration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "async-row",
            role: .assistant,
            markdown: newMarkdown,
            bubbleMaxWidth: 360
        )

        row.configure(oldConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: row.preparedMeasurementContext(for: 320, configuration: oldConfiguration))
        let oldTask = row.asyncPreparationTask
        XCTAssertNotNil(oldTask)
        try await loader.waitForRequestCount(1)

        row.configure(newConfiguration)
        let newContext = row.preparedMeasurementContext(for: 320, configuration: newConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: newContext)
        try await loader.waitForRequestCount(2)

        loader.finishRequest(at: 0)
        await oldTask?.value

        XCTAssertNil(row.acceptedAsyncKeyForTesting)
        XCTAssertEqual(row.pendingAsyncKeyForTesting, newContext.key)

        loader.finishRequest(at: 1)
        await row.waitForAcceptedAsyncKey { $0?.markdown == newMarkdown }

        XCTAssertEqual(row.acceptedAsyncKeyForTesting?.markdown, newMarkdown)
    }

    func testAsyncMarkdownPreparationRejectsStaleWidthResults() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Width-sensitive async markdown \(UUID().uuidString) " + String(repeating: "wrap ", count: 20)
        let loader = ControlledAsyncMarkdownLoader()
        defer { loader.finishAllRequests() }
        row.asyncDocumentLoaderForTesting = loader.load(markdown:context:)
        row.hydratesMarkdownImmediately = false
        let configuration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "async-width",
            role: .assistant,
            markdown: markdown,
            bubbleMaxWidth: 480
        )

        row.configure(configuration)
        let wideContext = row.preparedMeasurementContext(for: 440, configuration: configuration)
        row.scheduleAsyncMarkdownPreparation(for: wideContext)
        let wideTask = row.asyncPreparationTask
        XCTAssertNotNil(wideTask)
        try await loader.waitForRequestCount(1)
        let wideKey = wideContext.key

        let narrowContext = row.preparedMeasurementContext(for: 236, configuration: configuration)
        row.scheduleAsyncMarkdownPreparation(for: narrowContext)
        try await loader.waitForRequestCount(2)
        let narrowKey = narrowContext.key
        XCTAssertNotEqual(wideKey, narrowKey)

        loader.finishRequest(at: 0)
        await wideTask?.value

        XCTAssertNil(row.acceptedAsyncKeyForTesting)
        XCTAssertEqual(row.pendingAsyncKeyForTesting, narrowKey)

        loader.finishRequest(at: 1)
        await row.waitForAcceptedAsyncKey(narrowKey)

        XCTAssertEqual(row.acceptedAsyncKeyForTesting, narrowKey)
    }

    func testAsyncMarkdownPreparationRejectsStaleTypographyAndAppearanceResults() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Typography async markdown \(UUID().uuidString)"
        let loader = ControlledAsyncMarkdownLoader()
        defer { loader.finishAllRequests() }
        row.asyncDocumentLoaderForTesting = loader.load(markdown:context:)
        row.hydratesMarkdownImmediately = false
        row.appearance = NSAppearance(named: .aqua)
        let baseConfiguration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "async-style",
            role: .assistant,
            markdown: markdown,
            bubbleMaxWidth: 360
        )
        let typographyConfiguration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "async-style",
            role: .assistant,
            markdown: markdown,
            bubbleMaxWidth: 360,
            typography: AppKitMarkdownTypography(body: .systemFont(ofSize: 18))
        )

        row.configure(baseConfiguration)
        let firstContext = row.preparedMeasurementContext(for: 320, configuration: baseConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: firstContext)
        let firstTask = row.asyncPreparationTask
        XCTAssertNotNil(firstTask)
        try await loader.waitForRequestCount(1)
        let firstKey = firstContext.key

        row.configure(typographyConfiguration)
        let typographyContext = row.preparedMeasurementContext(for: 320, configuration: typographyConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: typographyContext)
        let typographyTask = row.asyncPreparationTask
        XCTAssertNotNil(typographyTask)
        try await loader.waitForRequestCount(2)
        let typographyKey = typographyContext.key
        XCTAssertNotEqual(firstKey, typographyKey)

        row.appearance = NSAppearance(named: .darkAqua)
        let darkContext = row.preparedMeasurementContext(for: 320, configuration: typographyConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: darkContext)
        try await loader.waitForRequestCount(3)
        let darkKey = darkContext.key
        XCTAssertNotEqual(typographyKey, darkKey)

        loader.finishRequest(at: 0)
        loader.finishRequest(at: 1)
        await firstTask?.value
        await typographyTask?.value

        XCTAssertNil(row.acceptedAsyncKeyForTesting)
        XCTAssertEqual(row.pendingAsyncKeyForTesting, darkKey)

        loader.finishRequest(at: 2)
        await row.waitForAcceptedAsyncKey(darkKey)

        XCTAssertEqual(row.acceptedAsyncKeyForTesting, darkKey)
    }

    func testRemovedRowsDoNotHydrateOrInvalidateWhenAsyncPreparationFinishes() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Removed async markdown \(UUID().uuidString)"
        let loader = ControlledAsyncMarkdownLoader()
        defer { loader.finishAllRequests() }
        var invalidationCount = 0
        row.asyncDocumentLoaderForTesting = loader.load(markdown:context:)
        row.hydratesMarkdownImmediately = false
        row.onHeightInvalidated = {
            invalidationCount += 1
        }
        let configuration = AppKitTranscriptTextBubbleRowView.Configuration(
            id: "removed-row",
            role: .assistant,
            markdown: markdown,
            bubbleMaxWidth: 360
        )
        row.configure(configuration)
        row.scheduleAsyncMarkdownPreparation(for: row.preparedMeasurementContext(for: 320, configuration: configuration))
        let removedTask = row.asyncPreparationTask
        XCTAssertNotNil(removedTask)
        try await loader.waitForRequestCount(1)
        let baselineInvalidationCount = invalidationCount

        row.resetAsyncMarkdownPreparation()
        loader.finishRequest(at: 0)
        await removedTask?.value

        XCTAssertNil(row.acceptedAsyncKeyForTesting)
        XCTAssertNil(row.pendingAsyncKeyForTesting)
        XCTAssertFalse(row.isMarkdownHydratedForTesting)
        XCTAssertEqual(invalidationCount, baselineInvalidationCount)
    }
}

private extension AppKitTranscriptTextBubbleRowView {
    func waitForAcceptedAsyncKey(
        _ expectedKey: AppKitMarkdownPreparedLayoutKey,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitForAcceptedAsyncKey({ $0 == expectedKey }, file: file, line: line)
    }

    func waitForAcceptedAsyncKey(
        _ predicate: (AppKitMarkdownPreparedLayoutKey?) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where !predicate(acceptedAsyncKeyForTesting) {
            await Task.yield()
        }
        if !predicate(acceptedAsyncKeyForTesting) {
            XCTFail("Expected accepted async markdown key", file: file, line: line)
        }
    }
}

@MainActor
private final class ControlledAsyncMarkdownLoader {
    private struct Request {
        let markdown: String
        var continuation: CheckedContinuation<AppMarkdownDocument, Never>?
    }

    private var requests: [Request] = []
    private var isReleased = false

    func load(
        markdown: String,
        context: AppMarkdownDocumentCacheContext
    ) async -> AppMarkdownDocument {
        if isReleased {
            return AppMarkdownParser().documentPreservingSource(for: markdown)
        }
        return await withCheckedContinuation { continuation in
            requests.append(Request(markdown: markdown, continuation: continuation))
        }
    }

    func finishRequest(
        at index: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard requests.indices.contains(index) else {
            XCTFail("No async markdown request at index \(index)", file: file, line: line)
            return
        }
        let request = requests[index]
        requests[index].continuation = nil
        request.continuation?.resume(returning: AppMarkdownParser().documentPreservingSource(for: request.markdown))
    }

    func finishAllRequests() {
        isReleased = true
        for index in requests.indices { finishRequest(at: index) }
    }

    func waitForRequestCount(
        _ count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while requests.count < count, ContinuousClock.now < deadline {
            await Task.yield()
        }
        _ = try XCTUnwrap(
            requests.count >= count ? true : nil,
            "Expected \(count) async markdown requests, got \(requests.count)",
            file: file,
            line: line
        )
    }
}
