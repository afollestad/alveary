import Foundation
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testPresentationBindingReportsAPendingItemAndClearsItOnDismiss() {
        var pending: String? = "pending"
        let isPresented = sidebarPresentationBinding(
            for: Binding(get: { pending }, set: { pending = $0 })
        )

        XCTAssertTrue(isPresented.wrappedValue)

        isPresented.wrappedValue = false

        XCTAssertNil(pending)
    }

    func testPresentationBindingReportsNoPendingItem() {
        var pending: String?
        let isPresented = sidebarPresentationBinding(
            for: Binding(get: { pending }, set: { pending = $0 })
        )

        XCTAssertFalse(isPresented.wrappedValue)
    }

    /// SwiftUI writes `true` back while a dialog animates in. The bridge only clears, because it
    /// has no item to restore — reacting to `true` would strand the dialog on a nil item.
    func testPresentationBindingIgnoresPresentationWrites() {
        var pending: String? = "pending"
        let isPresented = sidebarPresentationBinding(
            for: Binding(get: { pending }, set: { pending = $0 })
        )

        isPresented.wrappedValue = true

        XCTAssertEqual(pending, "pending")
    }
}
