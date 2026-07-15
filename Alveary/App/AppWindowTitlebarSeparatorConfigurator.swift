@preconcurrency import AppKit
import SwiftUI

struct AppWindowTitlebarSeparatorHairline: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let hairlineHeight = 1 / max(displayScale, 1)
            let separatorColor = colorScheme == .dark
                ? Color.white.opacity(0.11)
                : Color.black.opacity(0.04)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: size.width, height: hairlineHeight)),
                with: .color(separatorColor)
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 1)
        .allowsHitTesting(false)
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
