@preconcurrency import AppKit

@testable import Alveary

@MainActor
extension AppKitChatSurfaceViewTests {
    static func fileSuggestions(count: Int) -> [ComposerAutocompleteSuggestion] {
        (0..<count).map { index in
            ComposerAutocompleteSuggestion(
                id: "file-\(index)", title: "File \(index)",
                subtitle: nil,
                trailingText: nil,
                replacementText: "@file-\(index)", symbolName: "doc.text"
            )
        }
    }

    static func mouseEvent(type: NSEvent.EventType, location: NSPoint = .zero) -> NSEvent {
        NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )!
    }

    static func scrollEvent(deltaY: Int32, deltaX: Int32 = 0) -> NSEvent {
        NSEvent(cgEvent: CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0
        )!)!
    }
}

final class AutocompleteFixedHeightView: NSView {
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
