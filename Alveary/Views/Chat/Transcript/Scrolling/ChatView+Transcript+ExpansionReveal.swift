import SwiftUI

extension ChatTranscriptView {
    func transcriptRowExpansionBinding(for rowID: String) -> Binding<Bool> {
        Binding(get: { expandedTranscriptRows.contains(rowID) }, set: { isExpanded in
            let wasExpanded = expandedTranscriptRows.contains(rowID)
            if isExpanded {
                expandedTranscriptRows.insert(rowID)
                if !wasExpanded {
                    scheduleExpandedHeaderReveal(for: rowID)
                }
            } else {
                expandedTranscriptRows.remove(rowID)
                if pendingExpandedHeaderRevealID == rowID {
                    pendingExpandedHeaderRevealID = nil
                    pendingExpandedHeaderRevealToken = nil
                }
            }
        })
    }

    private func scheduleExpandedHeaderReveal(for rowID: String) {
        let token = UUID()
        pendingExpandedHeaderRevealID = rowID
        pendingExpandedHeaderRevealToken = token

        DispatchQueue.main.asyncAfter(
            deadline: .now() + toolExpansionAnimationDuration + expandedHeaderRevealLayoutDelay
        ) {
            guard pendingExpandedHeaderRevealID == rowID,
                  pendingExpandedHeaderRevealToken == token else {
                return
            }
            revealExpandedHeaderIfNeeded(for: rowID)
        }
    }

    private func revealExpandedHeaderIfNeeded(for rowID: String) {
        defer {
            pendingExpandedHeaderRevealID = nil
            pendingExpandedHeaderRevealToken = nil
        }

        guard expandedTranscriptRows.contains(rowID),
              let headerFrame = topLevelToolHeaderFrames[rowID],
              let metrics = latestMetrics else {
            return
        }

        guard let targetOffsetY = ChatTranscriptScrollBehavior.expandedHeaderRevealTargetOffset(
            headerFrame: headerFrame,
            metrics: metrics,
            inset: transcriptExpandedHeaderRevealInset
        ) else {
            return
        }

        let token = UUID()
        expandedHeaderRevealScrollToken = token
        scrollPosition.scrollTo(y: targetOffsetY)
        DispatchQueue.main.asyncAfter(deadline: .now() + expandedHeaderRevealScrollTimeout) {
            guard expandedHeaderRevealScrollToken == token else {
                return
            }
            expandedHeaderRevealScrollToken = nil
        }
    }
}
