import SwiftUI
import XCTest

@testable import Alveary

/// Exercises production key dispatch without the navigation policy suite's SwiftData fixtures.
@MainActor
extension SidebarViewTests {
    func testInlineEditingIgnoresSidebarKeysWithoutDispatch() {
        let keys: [KeyEquivalent] = [.upArrow, .downArrow, .leftArrow, .rightArrow, SidebarView.backspaceKey, .return]

        for key in keys {
            var actions: [SidebarKeyAction] = []
            let result = dispatchSidebarKey(key, isDragInFlight: false, isInlineEditingActive: true) { action in
                actions.append(action)
                return .handled
            }

            XCTAssertEqual(result, .ignored, "Key: \(key.character)")
            XCTAssertTrue(actions.isEmpty, "Key: \(key.character)")
        }
    }

    func testIdleSidebarKeysDispatchExactlyOnce() {
        let cases: [(key: KeyEquivalent, action: SidebarKeyAction)] = [
            (.upArrow, .verticalArrow(.upArrow)),
            (.downArrow, .verticalArrow(.downArrow)),
            (.leftArrow, .horizontalArrow(.leftArrow)),
            (.rightArrow, .horizontalArrow(.rightArrow)),
            (SidebarView.backspaceKey, .cleanup)
        ]
        let handlerResults: [KeyPress.Result] = [.handled, .ignored]

        for testCase in cases {
            for handlerResult in handlerResults {
                var actions: [SidebarKeyAction] = []
                let result = dispatchSidebarKey(testCase.key, isDragInFlight: false, isInlineEditingActive: false) { action in
                    actions.append(action)
                    return handlerResult
                }

                XCTAssertEqual(actions, [testCase.action])
                XCTAssertEqual(result, handlerResult)
            }
        }

        for key in [KeyEquivalent.return, KeyEquivalent("x")] {
            var actions: [SidebarKeyAction] = []
            let result = dispatchSidebarKey(key, isDragInFlight: false, isInlineEditingActive: false) { action in
                actions.append(action)
                return .handled
            }

            XCTAssertEqual(result, .ignored)
            XCTAssertTrue(actions.isEmpty)
        }
    }

    func testDragConsumesSidebarKeysBeforeInlineEditing() {
        let keys: [KeyEquivalent] = [.upArrow, .downArrow, .leftArrow, .rightArrow, SidebarView.backspaceKey, .return, "x"]

        for isEditing in [false, true] {
            for key in keys {
                var actions: [SidebarKeyAction] = []
                let result = dispatchSidebarKey(key, isDragInFlight: true, isInlineEditingActive: isEditing) { action in
                    actions.append(action)
                    return .ignored
                }

                XCTAssertEqual(result, .handled, "Key: \(key.character), editing: \(isEditing)")
                XCTAssertTrue(actions.isEmpty)
            }
        }
    }
}
