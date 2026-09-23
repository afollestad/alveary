import AppKit
import SwiftUI
import XCTest

/// Vends a `FocusState` binding for fixtures that must construct a view storing one, such as the
/// `==` fixtures for cards and rows that exclude the binding from equality.
///
/// Only a `View` can vend the binding, and reading `$focus` outside an installed body is a SwiftUI
/// runtime issue that fails `scripts/test.sh`. So this mounts a throwaway view and captures the
/// projection during its real body pass; storing the captured binding afterwards reads nothing.
@MainActor
func hostedFocusStateBinding<Wrapped: Hashable>(
    _ type: Wrapped.Type = Wrapped.self,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> FocusState<Wrapped?>.Binding {
    var captured: FocusState<Wrapped?>.Binding?
    let host = NSHostingView(rootView: FocusStateBindingVendor<Wrapped> { captured = $0 })
    host.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
    host.layoutSubtreeIfNeeded()
    return try XCTUnwrap(captured, "The hosted body never ran", file: file, line: line)
}

private struct FocusStateBindingVendor<Wrapped: Hashable>: View {
    let onBody: (FocusState<Wrapped?>.Binding) -> Void

    @FocusState private var focus: Wrapped?

    var body: some View {
        onBody($focus)
        return Color.clear
    }
}
