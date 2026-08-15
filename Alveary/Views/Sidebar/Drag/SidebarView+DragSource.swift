import SwiftUI

extension View {
    /// Always applies its modifier — a nil or disabled configuration flips the gesture's
    /// `GestureMask` instead of dropping to bare `self`. Enablement flips with drag state
    /// (`sidebarDragSourceIsEnabled` disables every other source while a drag is active), and a
    /// structural branch here changes the row's identity on each flip: section headers attach
    /// this at the row's top level, so `List` answered every drop's animated flip-back by
    /// remove-inserting all the headers, sliding them up and back down.
    func sidebarDragSource(_ configuration: SidebarRowDragConfiguration?) -> some View {
        modifier(SidebarDragSourceModifier(configuration: configuration))
    }
}

private struct SidebarDragSourceModifier: ViewModifier {
    let configuration: SidebarRowDragConfiguration?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // `.subviews` keeps the row's own drag inert while children — the zero-distance
            // toggle claim, a rename `TextField`'s text-selection drag — keep their gestures.
            .highPriorityGesture(dragGesture, including: isEnabled ? .all : .subviews)
    }

    private var isEnabled: Bool {
        configuration?.isEnabled == true
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(SidebarDragCoordinateSpace.name))
            .onChanged { value in
                configuration?.onChanged(value.location)
            }
            .onEnded { value in
                configuration?.onEnded(value.location)
            }
    }
}
