import AppKit

final class ChatComposerAccessoryGroupView: NSView {
    private let spacing: CGFloat
    private var accessories: [NSView] = []

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        guard !accessories.isEmpty else {
            return .zero
        }

        let widths = accessories
            .map(\.intrinsicContentSize.width)
            .filter { $0 != NSView.noIntrinsicMetric }
        let heights = accessories
            .map(\.intrinsicContentSize.height)
            .filter { $0 != NSView.noIntrinsicMetric }
        return NSSize(
            width: widths.reduce(0, +) + spacing * CGFloat(max(0, accessories.count - 1)),
            height: heights.max() ?? 0
        )
    }

    init(spacing: CGFloat) {
        self.spacing = spacing
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func addAccessory(_ view: NSView) {
        accessories.append(view)
        addSubview(view)
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        var nextX: CGFloat = 0
        for view in accessories {
            let size = view.intrinsicContentSize
            let width = size.width == NSView.noIntrinsicMetric ? view.fittingSize.width : size.width
            let height = size.height == NSView.noIntrinsicMetric ? bounds.height : size.height
            view.frame = NSRect(
                x: nextX,
                y: floor((bounds.height - height) / 2),
                width: width,
                height: height
            )
            nextX += width + spacing
        }
    }
}
