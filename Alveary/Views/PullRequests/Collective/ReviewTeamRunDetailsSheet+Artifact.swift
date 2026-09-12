import AppKit
import SwiftUI

/// Previews are bounded independently of stored bytes; copying retains the exact recorded text.
struct ReviewTeamHistoryArtifactView: View {
    let title: String
    let artifact: ReviewHistoryArtifact
    let run: ReviewTeamRun
    let store: ReviewTeamHistoryStore?
    @State private var isExpanded = false
    @State private var text: String?
    @State private var error: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let text {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(artifact.byteCount), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Copy full text") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }.secondaryActionButtonStyle()
                    }
                    Text(String(text.prefix(24_000)))
                        .font(.system(.callout, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if text.count > 24_000 {
                        Text("Preview limited to 24,000 characters. Copy full text to inspect the entire file.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView("Loading recorded text…").controlSize(.small)
                }
            }.padding(.vertical, 8)
        } label: {
            Text(title).fontWeight(.medium)
        }
        .task(id: isExpanded) {
            guard isExpanded, text == nil else { return }
            guard let store else { error = "Execution history storage is unavailable."; return }
            do {
                let data = try await store.read(artifact, conversationID: run.conversationID, runID: run.id)
                guard let value = String(data: data, encoding: .utf8) else {
                    error = "The recorded file is not UTF-8 text."
                    return
                }
                text = value
            } catch {
                self.error = "Recorded text unavailable: \(error.localizedDescription)"
            }
        }
    }
}
