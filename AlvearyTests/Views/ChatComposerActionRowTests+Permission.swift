import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testPermissionButtonUsesMetadataPresentationAndCompactDropdownMetrics() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(
            makeConfiguration(
                mode: .idle,
                supportedPermissionModes: [
                    .init(
                        value: "never",
                        title: "Full access",
                        description: "Unrestricted access to the internet and any file on your computer.",
                        symbolName: "exclamationmark.shield",
                        isWarning: true
                    )
                ],
                selectedPermissionMode: "never"
            )
        )

        let button = row.permissionButton
        XCTAssertEqual(button.accessibilityLabel(), "Permissions")
        XCTAssertEqual(button.accessibilityValue() as? String, "Full access")
        XCTAssertEqual(button.intrinsicContentSize.height, 24)
        #if DEBUG
        XCTAssertEqual(button.debugTitle, "Full access")
        XCTAssertEqual(button.debugSymbolName, "exclamationmark.shield")
        XCTAssertEqual(button.debugIconRotationRadians, 0, accuracy: 0.0001)
        XCTAssertTrue(button.debugIsWarning)
        XCTAssertEqual(button.debugTextChevronSpacing, button.debugIconTextSpacing)
        #endif
    }
}
