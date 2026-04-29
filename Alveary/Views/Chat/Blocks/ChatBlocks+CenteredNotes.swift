import SwiftUI

struct CenteredTranscriptNote: View {
    let kind: CenteredTranscriptNoteKind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")

            Text(kind.text)
        }
        .transcriptFont(.body, weight: .medium)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 24)
    }
}

struct TurnInterruptedNote: View {
    var body: some View {
        CenteredTranscriptNote(kind: .interrupted)
    }
}
