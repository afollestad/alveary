@preconcurrency import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitChatSurfaceViewTests: XCTestCase {
    func testLayoutPinsComposerToBottomAndGivesRemainingHeightToContent() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = FixedHeightView(height: 44)

        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 176))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 176, width: 300, height: 44))
    }

    func testLayoutRemeasuresComposerWhenItsHeightChanges() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = MutableHeightView(height: 44)
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        composer.height = 70
        surface.needsLayout = true
        surface.layoutSubtreeIfNeeded()

        XCTAssertEqual(content.frame, NSRect(x: 0, y: 0, width: 300, height: 150))
        XCTAssertEqual(composer.frame, NSRect(x: 0, y: 150, width: 300, height: 70))
    }

    func testHostedComposerSizeInvalidationRequestsSurfaceLayout() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let composer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        surface.configure(contentView: content, composerView: composer)
        surface.layoutSubtreeIfNeeded()

        surface.needsLayout = false
        composer.invalidateIntrinsicContentSize()

        XCTAssertTrue(surface.needsLayout)
    }

    func testReplacingHostedComposerClearsOldSizeInvalidationCallback() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let content = FixedHeightView(height: 80)
        let firstComposer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        let secondComposer = AppKitChatSurfaceHostingView(rootView: AnyView(EmptyView()))
        surface.configure(contentView: content, composerView: firstComposer)
        surface.configure(contentView: content, composerView: secondComposer)
        surface.layoutSubtreeIfNeeded()

        surface.needsLayout = false
        firstComposer.invalidateIntrinsicContentSize()

        XCTAssertFalse(surface.needsLayout)
    }

    func testConfigureReplacesHostedViewsWithoutLeavingOldSubviews() {
        let surface = AppKitChatSurfaceView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        let firstContent = FixedHeightView(height: 20)
        let firstComposer = FixedHeightView(height: 40)
        let secondContent = FixedHeightView(height: 30)
        let secondComposer = FixedHeightView(height: 50)

        surface.configure(contentView: firstContent, composerView: firstComposer)
        surface.configure(contentView: secondContent, composerView: secondComposer)

        XCTAssertFalse(surface.subviews.contains(firstContent))
        XCTAssertFalse(surface.subviews.contains(firstComposer))
        XCTAssertTrue(surface.subviews.contains(secondContent))
        XCTAssertTrue(surface.subviews.contains(secondComposer))
        XCTAssertEqual(surface.subviews.count, 2)
    }
}

private final class FixedHeightView: NSView {
    private let fixedHeight: CGFloat

    init(height: CGFloat) {
        fixedHeight = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: fixedHeight)
    }
}

private final class MutableHeightView: NSView {
    var height: CGFloat {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    init(height: CGFloat) {
        self.height = height
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override var fittingSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}
