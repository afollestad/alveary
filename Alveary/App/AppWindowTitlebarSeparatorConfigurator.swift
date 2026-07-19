@preconcurrency import AppKit
import SwiftUI

struct AppSeparatorHairline: View {
    enum Surface {
        case titlebar
        case paneHeader
    }

    let surface: Surface

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(separatorColor)
            .frame(maxWidth: .infinity)
            .frame(height: 1 / max(displayScale, 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var separatorColor: Color {
        // The system-managed titlebar edge contributes different pixels by appearance.
        // These overlays are calibrated so both surfaces resolve to the same visible hairline.
        switch (surface, colorScheme) {
        case (.titlebar, .dark):
            .clear
        case (.titlebar, .light):
            Color.black.opacity(0.05)
        case (.paneHeader, .dark):
            Color.white.opacity(0.08)
        case (.paneHeader, .light):
            Color.black.opacity(25.0 / 255.0)
        @unknown default:
            .clear
        }
    }
}

struct AppWindowTitlebarSeparatorConfigurator: NSViewRepresentable {
    let style: NSTitlebarSeparatorStyle

    func makeNSView(context: Context) -> AppWindowTitlebarSeparatorAnchorView {
        AppWindowTitlebarSeparatorAnchorView(style: style)
    }

    func updateNSView(_ nsView: AppWindowTitlebarSeparatorAnchorView, context: Context) {
        nsView.style = style
    }
}

final class AppWindowTitlebarSeparatorAnchorView: NSView {
    var style: NSTitlebarSeparatorStyle {
        didSet {
            applyStyle()
        }
    }

    init(style: NSTitlebarSeparatorStyle) {
        self.style = style
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyStyle()
    }

    private func applyStyle() {
        window?.titlebarSeparatorStyle = style
    }
}
