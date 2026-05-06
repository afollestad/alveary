@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptTextBubbleRowTests {
    func testAsyncMarkdownPreparationAcceptsMatchingLayoutInputs() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Async prepared markdown \(UUID().uuidString) with `code`."
        let loader = ControlledAsyncMarkdownLoader()
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
        await loader.waitForRequestCount(1)
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
        await loader.waitForRequestCount(1)

        row.configure(newConfiguration)
        let newContext = row.preparedMeasurementContext(for: 320, configuration: newConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: newContext)
        await loader.waitForRequestCount(2)

        loader.finishRequest(at: 0)
        await Task.yield()

        XCTAssertNil(row.acceptedAsyncKeyForTesting)

        loader.finishRequest(at: 1)
        await row.waitForAcceptedAsyncKey { $0?.markdown == newMarkdown }

        XCTAssertEqual(row.acceptedAsyncKeyForTesting?.markdown, newMarkdown)
    }

    func testAsyncMarkdownPreparationRejectsStaleWidthResults() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Width-sensitive async markdown \(UUID().uuidString) " + String(repeating: "wrap ", count: 20)
        let loader = ControlledAsyncMarkdownLoader()
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
        await loader.waitForRequestCount(1)
        let wideKey = wideContext.key

        let narrowContext = row.preparedMeasurementContext(for: 236, configuration: configuration)
        row.scheduleAsyncMarkdownPreparation(for: narrowContext)
        await loader.waitForRequestCount(2)
        let narrowKey = narrowContext.key
        XCTAssertNotEqual(wideKey, narrowKey)

        loader.finishRequest(at: 0)
        await Task.yield()

        XCTAssertNil(row.acceptedAsyncKeyForTesting)

        loader.finishRequest(at: 1)
        await row.waitForAcceptedAsyncKey(narrowKey)

        XCTAssertEqual(row.acceptedAsyncKeyForTesting, narrowKey)
    }

    func testAsyncMarkdownPreparationRejectsStaleTypographyAndAppearanceResults() async throws {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Typography async markdown \(UUID().uuidString)"
        let loader = ControlledAsyncMarkdownLoader()
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
        await loader.waitForRequestCount(1)
        let firstKey = firstContext.key

        row.configure(typographyConfiguration)
        let typographyContext = row.preparedMeasurementContext(for: 320, configuration: typographyConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: typographyContext)
        await loader.waitForRequestCount(2)
        let typographyKey = typographyContext.key
        XCTAssertNotEqual(firstKey, typographyKey)

        row.appearance = NSAppearance(named: .darkAqua)
        let darkContext = row.preparedMeasurementContext(for: 320, configuration: typographyConfiguration)
        row.scheduleAsyncMarkdownPreparation(for: darkContext)
        await loader.waitForRequestCount(3)
        let darkKey = darkContext.key
        XCTAssertNotEqual(typographyKey, darkKey)

        loader.finishRequest(at: 0)
        loader.finishRequest(at: 1)
        await Task.yield()

        XCTAssertNil(row.acceptedAsyncKeyForTesting)

        loader.finishRequest(at: 2)
        await row.waitForAcceptedAsyncKey(darkKey)

        XCTAssertEqual(row.acceptedAsyncKeyForTesting, darkKey)
    }

    func testRemovedRowsDoNotHydrateOrInvalidateWhenAsyncPreparationFinishes() async {
        let row = AppKitTranscriptTextBubbleRowView()
        let markdown = "Removed async markdown \(UUID().uuidString)"
        let loader = ControlledAsyncMarkdownLoader()
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
        await loader.waitForRequestCount(1)
        let baselineInvalidationCount = invalidationCount

        row.resetAsyncMarkdownPreparation()
        loader.finishRequest(at: 0)
        await Task.yield()

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
        let continuation: CheckedContinuation<AppMarkdownDocument, Never>
    }

    private var requests: [Request] = []

    func load(
        markdown: String,
        context: AppMarkdownDocumentCacheContext
    ) async -> AppMarkdownDocument {
        await withCheckedContinuation { continuation in
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
        request.continuation.resume(returning: AppMarkdownParser().documentPreservingSource(for: request.markdown))
    }

    func waitForRequestCount(
        _ count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 where requests.count < count {
            await Task.yield()
        }
        if requests.count < count {
            XCTFail("Expected \(count) async markdown requests, got \(requests.count)", file: file, line: line)
        }
    }
}
