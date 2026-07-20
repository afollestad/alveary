import SwiftUI

extension ContentView {
    var activeDiffViewerTopSectionFraction: Binding<CGFloat> {
        Binding(
            get: {
                diffViewerMode == .commits
                    ? diffViewerCommitsTopSectionFraction
                    : diffViewerTopSectionFraction
            },
            set: { newValue in
                switch diffViewerMode {
                case .currentChanges:
                    diffViewerTopSectionFraction = newValue
                case .commits:
                    diffViewerCommitsTopSectionFraction = newValue
                }
            }
        )
    }

    func persistDiffViewerTopSectionFraction(_ fraction: CGFloat, mode: DiffViewerMode) {
        settingsService.update {
            switch mode {
            case .currentChanges:
                $0.diffViewerTopSectionFraction = fraction
            case .commits:
                $0.diffViewerCommitsTopSectionFraction = fraction
            }
        }
    }

    func persistDiffViewerMode(_ mode: DiffViewerMode) {
        settingsService.update {
            $0.diffViewerMode = mode
        }
    }

    func persistTerminalPaneHeight(_ height: CGFloat) {
        settingsService.update {
            $0.terminalPaneHeight = height
        }
    }
}
