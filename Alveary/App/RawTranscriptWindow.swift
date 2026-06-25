#if DEBUG
import SwiftData
import SwiftUI

private let rawTranscriptCollapsedLineLimit = 10
private let rawTranscriptBottomID = "raw-transcript-bottom"
private let rawTranscriptNearBottomThreshold: CGFloat = 16
private let rawTranscriptProgrammaticScrollTimeout: TimeInterval = 0.4

struct RawTranscriptWindowRequest: Codable, Hashable {
    static let sceneID = "raw-transcript"

    let conversationID: String
    let threadName: String
    let conversationTitle: String

    var windowTitle: String {
        "\(threadName) (\(conversationTitle))"
    }
}

struct RawTranscriptWindow: View {
    let request: RawTranscriptWindowRequest

    @Query private var records: [ConversationEventRecord]
    @State private var expandedRecordIDs: Set<String> = []
    @State private var isFollowing = true
    @State private var latestContentFrame: CGRect?
    @State private var latestContainerHeight: CGFloat = 0
    @State private var pendingBottomScrollToken: UUID?

    init(request: RawTranscriptWindowRequest) {
        self.request = request
        let conversationID = request.conversationID
        _records = Query(
            filter: #Predicate { $0.conversationId == conversationID },
            sort: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.id)
            ]
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records, id: \.id) { record in
                            RawTranscriptRow(
                                record: record,
                                isExpanded: expandedRecordIDs.contains(record.id),
                                onToggleExpanded: { toggleExpandedRecord(id: record.id) }
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
                .onChange(of: records.count) { oldCount, newCount in
                    handleRecordCountChange(oldCount: oldCount, newCount: newCount, proxy: proxy)
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
        .navigationTitle(request.windowTitle)
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

    private func handleRecordCountChange(oldCount: Int, newCount: Int, proxy: ScrollViewProxy) {
        guard newCount > oldCount else {
            return
        }

        if shouldForceBottomScrollForLatestRecord() {
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

    private func toggleExpandedRecord(id: String) {
        if expandedRecordIDs.contains(id) {
            expandedRecordIDs.remove(id)
        } else {
            expandedRecordIDs.insert(id)
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

    private func shouldForceBottomScrollForLatestRecord() -> Bool {
        guard let latestRecord = records.last else {
            return false
        }
        return latestRecord.type == "message" && latestRecord.role == "user"
    }

    private func isNearBottom(_ contentFrame: CGRect, containerHeight: CGFloat) -> Bool {
        contentFrame.maxY <= containerHeight + rawTranscriptNearBottomThreshold
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
    let record: ConversationEventRecord
    let isExpanded: Bool
    let onToggleExpanded: () -> Void

    private var text: String {
        RawTranscriptRecordFormatter.text(for: record)
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

    private var toggleTitle: String {
        isExpanded ? "Show less" : "Show \(lines.count - rawTranscriptCollapsedLineLimit) more lines"
    }

    private var isUserMessage: Bool {
        record.role == "user"
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
            Text(verbatim: displayedText)
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

private enum RawTranscriptRecordFormatter {
    static func text(for record: ConversationEventRecord) -> String {
        var lines: [String] = []
        append("id", record.id, to: &lines)
        append("conversationId", record.conversationId, to: &lines)
        append("timestamp", "\(record.timestamp)", to: &lines)
        append("type", record.type, to: &lines)
        append("role", record.role, to: &lines)
        append("content", record.content, to: &lines)
        append("toolId", record.toolId, to: &lines)
        append("toolName", record.toolName, to: &lines)
        append("toolInput", record.toolInput, to: &lines)
        append("toolApprovalStatus", record.toolApprovalStatus, to: &lines)
        append("toolOutput", record.toolOutput, to: &lines)
        append("toolOutputStderr", record.toolOutputStderr, to: &lines)
        append("parentToolUseId", record.parentToolUseId, to: &lines)
        append("callerAgent", record.callerAgent, to: &lines)
        appendIfTrue("toolOutputInterrupted", record.toolOutputInterrupted, to: &lines)
        appendIfTrue("toolOutputIsImage", record.toolOutputIsImage, to: &lines)
        appendIfTrue("toolOutputNoOutputExpected", record.toolOutputNoOutputExpected, to: &lines)
        appendIfTrue("isError", record.isError, to: &lines)
        appendIfNonZero("tokenInput", record.tokenInput, to: &lines)
        appendIfNonZero("tokenOutput", record.tokenOutput, to: &lines)
        appendIfNonZero("tokenCacheRead", record.tokenCacheRead, to: &lines)
        appendIfNonZero("tokenCacheCreation", record.tokenCacheCreation, to: &lines)
        appendIfNonZero("durationMs", record.durationMs, to: &lines)
        appendIfNonZero("costUsd", record.costUsd, to: &lines)
        appendIfTrue("costUsdReported", record.costUsdReported, to: &lines)
        append("providerModelId", record.providerModelId, to: &lines)
        appendIfNonZero("contextWindowSize", record.contextWindowSize ?? 0, to: &lines)
        append("notificationType", record.notificationType, to: &lines)
        append("stopReason", record.stopReason, to: &lines)
        return lines.joined(separator: "\n")
    }

    private static func append(_ label: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else {
            return
        }

        if value.contains("\n") {
            lines.append("\(label):")
            lines.append(value)
        } else {
            lines.append("\(label): \(value)")
        }
    }

    private static func appendIfTrue(_ label: String, _ value: Bool, to lines: inout [String]) {
        guard value else {
            return
        }
        lines.append("\(label): true")
    }

    private static func appendIfNonZero(_ label: String, _ value: Int, to lines: inout [String]) {
        guard value != 0 else {
            return
        }
        lines.append("\(label): \(value)")
    }

    private static func appendIfNonZero(_ label: String, _ value: Double, to lines: inout [String]) {
        guard value != 0 else {
            return
        }
        lines.append("\(label): \(value)")
    }
}
#endif
