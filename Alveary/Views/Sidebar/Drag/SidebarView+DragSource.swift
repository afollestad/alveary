import SwiftUI

extension View {
    @ViewBuilder
    func sidebarDragSource(_ configuration: SidebarRowDragConfiguration?) -> some View {
        if let configuration, configuration.isEnabled {
            modifier(SidebarDragSourceModifier(configuration: configuration))
        } else {
            self
        }
    }
}

private struct SidebarDragSourceModifier: ViewModifier {
    let configuration: SidebarRowDragConfiguration

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(SidebarDragCoordinateSpace.name))
            .onChanged { value in
                configuration.onChanged(value.location)
            }
            .onEnded { value in
                configuration.onEnded(value.location)
            }
    }
}
