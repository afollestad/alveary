import AppKit
import SwiftUI

extension SidebarView {
    /// The right-click surface for the sidebar's empty area, mounted in the list overlay for the
    /// same reason `SidebarDragMonitor` is: it has to sit above virtualized rows and outlive them.
    ///
    /// `SecondaryClickTarget` reports every secondary click in the list's bounds; the provider
    /// answers with a menu only below the last row, so a click on a row still reaches that row's
    /// own `contextMenu`. Returning `nil` declines the click entirely.
    var sidebarEmptyAreaMenuTarget: some View {
        SecondaryClickTarget(menuProvider: sidebarEmptyAreaMenu(at:))
    }

    private func sidebarEmptyAreaMenu(at point: CGPoint) -> NSMenu? {
        guard !isSidebarDragInteractionInFlight,
              !isSidebarInlineEditingActive,
              sidebarEmptyAreaContainsPoint(point, geometry: sidebarDragGeometry.frames) else {
            return nil
        }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "New Section...",
            action: #selector(SidebarEmptyAreaMenuHandler.newSection(_:)),
            keyEquivalent: ""
        )
        let handler = SidebarEmptyAreaMenuHandler { beginCreatingSection() }
        item.target = handler
        // The menu is the only strong reference to its handler for as long as it is open.
        item.representedObject = handler
        menu.addItem(item)
        return menu
    }

    /// The pending name field, rendered last because a created section appends at the bottom.
    @ViewBuilder
    var pendingNewSectionRow: some View {
        if isCreatingSection {
            SidebarNewSectionRow(
                onCommit: { commitNewSection(name: $0) },
                onCancel: { cancelCreatingSection() }
            )
        }
    }

    func beginCreatingSection() {
        guard !isSidebarInlineEditingActive else {
            return
        }
        isCreatingSection = true
    }

    /// Commits the pending new-section name, or cancels when it is empty or the service refuses.
    func commitNewSection(name: String) {
        isCreatingSection = false
        guard let validatedName = sidebarNewSectionNameCommitValue(name) else {
            claimSidebarFocus()
            return
        }
        do {
            try viewModel.createSection(name: validatedName)
        } catch {
            viewModel.presentSidebarError(error)
        }
        claimSidebarFocus()
    }

    func cancelCreatingSection() {
        isCreatingSection = false
        claimSidebarFocus()
    }

    /// Removes a custom section; its member threads fall back to `Tasks`, so a selected member
    /// stays selected and simply renders in a different group.
    func removeSection(id: String) {
        if editingSectionID == id {
            editingSectionID = nil
        }
        collapsedSections.remove(.custom(id))
        do {
            try viewModel.removeSection(id: id)
        } catch {
            viewModel.presentSidebarError(error)
        }
        claimSidebarFocus()
    }
}

/// Owns the `@objc` action an `NSMenuItem` needs. `SidebarView` is a struct, so it cannot be a
/// menu-item target itself; the item retains this through `representedObject`.
@MainActor
final class SidebarEmptyAreaMenuHandler: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc
    func newSection(_ sender: NSMenuItem) {
        action()
    }
}

/// Whether a click lands in the sidebar's empty area — inside the list, below every published row.
///
/// The point arrives in the overlay's own coordinates, the same frame the drag monitor reports
/// in, and the published row frames live in the drag named space — so the point is converted
/// through `sidebarDragLocationInNamedSpace` before comparing, exactly as pointer drags are.
/// Row frames reach here through the drag-geometry preference pipeline, which publishes outside
/// drags too, so "below the last row" is exact rather than estimated. Gaps *between* rows are
/// deliberately not empty area: the pending name field appears at the bottom regardless, so
/// treating an inter-row gap as a create gesture would only surprise.
func sidebarEmptyAreaContainsPoint(
    _ monitorPoint: CGPoint,
    geometry: [SidebarDragGeometryRole: [CGRect]]
) -> Bool {
    guard let viewport = geometry[.viewport]?.sidebarUnion else {
        return false
    }
    let point = sidebarDragLocationInNamedSpace(monitorLocation: monitorPoint, viewport: viewport)
    guard point.x >= viewport.minX, point.x <= viewport.maxX,
          point.y >= viewport.minY, point.y <= viewport.maxY else {
        return false
    }
    let contentMaxY = geometry
        .filter { $0.key != .viewport }
        .values
        .flatMap { $0 }
        .map(\.maxY)
        .max()
    guard let contentMaxY else {
        // Nothing published yet: the whole viewport is empty by definition.
        return true
    }
    return point.y > contentMaxY
}
