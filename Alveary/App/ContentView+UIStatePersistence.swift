import SwiftUI

extension ContentView {
    func persistDiffViewerWidth(_ width: CGFloat) {
        settingsService.update {
            $0.diffViewerWidth = width
        }
    }

    func persistDiffViewerTopSectionFraction(_ fraction: CGFloat) {
        settingsService.update {
            $0.diffViewerTopSectionFraction = fraction
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
