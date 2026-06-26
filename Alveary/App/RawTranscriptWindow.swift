#if DEBUG
import Foundation
import SwiftData
import SwiftUI

private let rawTranscriptCollapsedLineLimit = 10
private let rawTranscriptBottomID = "raw-transcript-bottom"
private let rawTranscriptNearBottomThreshold: CGFloat = 16
private let rawTranscriptProgrammaticScrollTimeout: TimeInterval = 0.4
private let rawTranscriptPollIntervalNanoseconds: UInt64 = 500_000_000

struct RawTranscriptWindowRequest: Codable, Hashable {
    static let sceneID = "raw-transcript"

    let conversationID: String
    let threadName: String
    let conversationTitle: String
    let providerID: String?
    let providerSessionID: String?
    let providerSessionWorkingDirectory: String?

    var windowTitle: String {
        "\(threadName) (\(conversationTitle))"
    }
}

struct RawTranscriptWindow: View {
    let request: RawTranscriptWindowRequest

    @Query private var conversations: [Conversation]
    @State private var entries: [RawTranscriptLogEntry] = []
    @State private var expandedEntryIDs: Set<String> = []
    @State private var isFollowing = true
    @State private var latestContentFrame: CGRect?
    @State private var latestContainerHeight: CGFloat = 0
    @State private var pendingBottomScrollToken: UUID?

    init(request: RawTranscriptWindowRequest) {
        self.request = request
        let conversationID = request.conversationID
        _conversations = Query(filter: #Predicate { $0.id == conversationID })
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            RawTranscriptRow(
                                entry: entry,
                                isExpanded: expandedEntryIDs.contains(entry.id),
                                onToggleExpanded: { toggleExpandedEntry(id: entry.id) }
                            )
                            Divider()
                        }
                        bottomAnchor
                    }
                    .background(contentFrameTracker)
                }
                .coordinateSpace(name: RawTranscriptScrollCoordinateSpace.name)
                .onAppear {
                    scrollToBottom(proxy: proxy, forceFollow: true)
                }
                .onChange(of: entries.count) { oldCount, newCount in
                    handleEntryCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
                }
                .onPreferenceChange(RawTranscriptContentFramePreferenceKey.self) { contentFrame in
                    guard let contentFrame else {
                        return
                    }
                    handleContentFrameChange(contentFrame, containerHeight: geometry.size.height)
                }
                .overlay(alignment: .bottom) {
                    ScrollToLatestButton {
                        scrollToBottom(proxy: proxy, forceFollow: true)
                    }
                    .opacity(isFollowing ? 0 : 1)
                    .allowsHitTesting(!isFollowing)
                    .accessibilityHidden(isFollowing)
                    .padding(.bottom, 12)
                    .animation(.easeInOut(duration: 0.18), value: isFollowing)
                }
            }
        }
        .task(id: transcriptSource) {
            await followRawTranscript(source: transcriptSource)
        }
        .navigationTitle(windowTitle)
    }

    private var transcriptSource: RawTranscriptSource? {
        let conversation = conversations.first
        let providerID = conversation?.providerSessionProviderId ?? request.providerID ?? conversation?.provider
        let providerSessionID = conversation?.providerSessionId ?? request.providerSessionID
        let workingDirectory = conversation?.providerSessionWorkingDirectory ?? request.providerSessionWorkingDirectory
        return RawTranscriptSource(
            providerID: providerID,
            providerSessionID: providerSessionID,
            workingDirectory: workingDirectory
        )
    }

    private var windowTitle: String {
        guard let conversation = conversations.first else {
            return request.windowTitle
        }

        let threadName = conversation.thread?.displayName() ?? request.threadName
        return "\(threadName) (\(conversation.displayName()))"
    }

    private var bottomAnchor: some View {
        Color.clear
            .frame(height: 1)
            .id(rawTranscriptBottomID)
    }

    private var contentFrameTracker: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RawTranscriptContentFramePreferenceKey.self,
                value: proxy.frame(in: .named(RawTranscriptScrollCoordinateSpace.name))
            )
        }
    }

    private func handleEntryCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        guard newCount > oldCount else {
            return
        }

        if shouldForceBottomScrollForLatestEntry() {
            scrollToBottom(proxy: proxy, forceFollow: true)
        } else if isFollowing {
            scrollToBottom(proxy: proxy, forceFollow: false)
        }
    }

    private func handleContentFrameChange(_ contentFrame: CGRect, containerHeight: CGFloat) {
        latestContentFrame = contentFrame
        latestContainerHeight = containerHeight

        if isNearBottom(contentFrame, containerHeight: containerHeight) {
            isFollowing = true
            return
        }
        guard pendingBottomScrollToken == nil else {
            return
        }
        isFollowing = false
    }

    private func toggleExpandedEntry(id: String) {
        if expandedEntryIDs.contains(id) {
            expandedEntryIDs.remove(id)
        } else {
            expandedEntryIDs.insert(id)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, forceFollow: Bool) {
        if forceFollow {
            isFollowing = true
        }

        let token = UUID()
        pendingBottomScrollToken = token
        proxy.scrollTo(rawTranscriptBottomID, anchor: .bottom)
        DispatchQueue.main.async {
            guard pendingBottomScrollToken == token else {
                return
            }
            proxy.scrollTo(rawTranscriptBottomID, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard pendingBottomScrollToken == token else {
                return
            }
            proxy.scrollTo(rawTranscriptBottomID, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rawTranscriptProgrammaticScrollTimeout) {
            guard pendingBottomScrollToken == token else {
                return
            }
            pendingBottomScrollToken = nil
            guard let latestContentFrame else {
                return
            }
            isFollowing = isNearBottom(latestContentFrame, containerHeight: latestContainerHeight)
        }
    }

    private func shouldForceBottomScrollForLatestEntry() -> Bool {
        entries.last?.isUserMessage == true
    }

    private func isNearBottom(_ contentFrame: CGRect, containerHeight: CGFloat) -> Bool {
        contentFrame.maxY <= containerHeight + rawTranscriptNearBottomThreshold
    }

    @MainActor
    private func followRawTranscript(source: RawTranscriptSource?) async {
        entries = []
        expandedEntryIDs = []
        guard let source else {
            return
        }

        var reader = RawTranscriptJSONLineReader(sourceID: source.id)
        var currentFileURL: URL?

        while !Task.isCancelled {
            guard let fileURL = currentFileURL ?? source.fileURL() else {
                try? await Task.sleep(nanoseconds: rawTranscriptPollIntervalNanoseconds)
                continue
            }

            if currentFileURL != fileURL {
                currentFileURL = fileURL
                reader = RawTranscriptJSONLineReader(sourceID: source.id)
                entries = []
                expandedEntryIDs = []
            }

            let newEntries = reader.readAvailableEntries(from: fileURL)
            if !newEntries.isEmpty {
                entries.append(contentsOf: newEntries)
            }

            try? await Task.sleep(nanoseconds: rawTranscriptPollIntervalNanoseconds)
        }
    }
}

private enum RawTranscriptScrollCoordinateSpace {
    static let name = "rawTranscriptScroll"
}

private struct RawTranscriptContentFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct RawTranscriptRow: View {
    let entry: RawTranscriptLogEntry
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var text: String {
        entry.text
    }

    private var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private var isExpandable: Bool {
        lines.count > rawTranscriptCollapsedLineLimit
    }

    private var displayedText: String {
        guard isExpandable, !isExpanded else {
            return text
        }
        return lines.prefix(rawTranscriptCollapsedLineLimit).joined(separator: "\n")
    }

    private var highlightedText: AttributedString {
        SyntaxHighlighter.highlighted(displayedText, language: "json", colorScheme: colorScheme)
    }

    private var toggleTitle: String {
        isExpanded ? "Show less" : "Show \(lines.count - rawTranscriptCollapsedLineLimit) more lines"
    }

    private var isUserMessage: Bool {
        entry.isUserMessage
    }

    private var alignment: Alignment {
        isUserMessage ? .trailing : .leading
    }

    private var horizontalAlignment: HorizontalAlignment {
        isUserMessage ? .trailing : .leading
    }

    private var textAlignment: TextAlignment {
        isUserMessage ? .trailing : .leading
    }

    var body: some View {
        VStack(alignment: horizontalAlignment, spacing: 6) {
            Text(highlightedText)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(textAlignment)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: alignment)

            if isExpandable {
                Button(toggleTitle, action: onToggleExpanded)
                    .buttonStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
#endif
