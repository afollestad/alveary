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

    func persistTerminalPaneHeight(_ height: CGFloat) {
        settingsService.update {
            $0.terminalPaneHeight = height
        }
    }
}
