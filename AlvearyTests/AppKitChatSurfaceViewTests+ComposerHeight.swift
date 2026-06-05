@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    func testPreferredComposerHeightChangeShrinksComposerImmediatelyWhenRequested() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = SurfaceLayoutCountingView(height: 80)
        let composer = SurfaceMutableHeightView(height: 100)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        composer.height = 44
        surface.layoutPreferredComposerHeightChange(animated: false)

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 176))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 176, width: 300, height: 44))
        XCTAssertGreaterThan(content.layoutCount, 0)
    }

    func testPreferredComposerHeightChangeRestoresComposerImmediatelyWhenAnimationIsDisabledForTesting() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        surface.disableHeightAnimationForTesting = true
        let content = SurfaceFixedHeightView(height: 80)
        let composer = SurfaceMutableHeightView(height: 44)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        composer.height = 100
        surface.layoutPreferredComposerHeightChange()

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 120))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 120, width: 300, height: 100))
    }
}

private final class SurfaceFixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
}

private final class SurfaceMutableHeightView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }
}

private final class SurfaceLayoutCountingView: NSView {
    private let fixedHeight: CGFloat
    private(set) var layoutCount = 0

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }
    override var fittingSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight) }

    override func layout() {
        super.layout()
        layoutCount += 1
    }
}
