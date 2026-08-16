import AppKit
import SwiftUI

/// The sidebar's secondary-click menus, both popped as real `NSMenu`s from one event-monitored
/// overlay: a custom section header's `Rename...` / `Remove Section...`, and the empty area's
/// `New Section...`.
///
/// Neither can be a SwiftUI `contextMenu`. The empty area is not a row at all, and a header's
/// menu has to outline the whole section — `contextMenu` only ever highlights the single row it
/// is attached to, and it derives that highlight from the row's *padded* frame, which on a
/// section header includes the divider's breathing room above the title.
extension SidebarView {
    /// The right-click surface for the sidebar, mounted in the list overlay for the same reason
    /// `SidebarDragMonitor` is: it has to sit above virtualized rows and outlive them.
    ///
    /// `SecondaryClickTarget` reports every secondary click in the list's bounds; the provider
    /// answers only for a custom section header or the region below the last row, so a click on
    /// any other row still reaches that row's own `contextMenu`. Returning `nil` declines the
    /// click entirely.
    func sidebarSecondaryClickMenuTarget(context: SidebarRenderContext) -> some View {
        SecondaryClickTarget(menuProvider: { point in
            sidebarSecondaryClickMenu(at: point, context: context)
        })
    }

    private func sidebarSecondaryClickMenu(at point: CGPoint, context: SidebarRenderContext) -> NSMenu? {
        guard !isSidebarDragInteractionInFlight else {
            return nil
        }
        if let menu = sidebarSectionHeaderMenu(at: point, context: context) {
            return menu
        }
        return sidebarEmptyAreaMenu(at: point)
    }

    /// A custom section header's menu, which also lights the section it belongs to.
    ///
    /// The highlight is captured here rather than read from `sidebarDragGeometry` in `body`,
    /// which must never observe that store (see `Alveary/Views/Sidebar/Drag/AGENTS.md`). A
    /// captured frame cannot go stale while the menu is up: popping one runs a nested event loop,
    /// so the list underneath neither scrolls nor relayouts until the menu closes.
    private func sidebarSectionHeaderMenu(at point: CGPoint, context: SidebarRenderContext) -> NSMenu? {
        guard let highlight = sidebarSecondaryClickSectionHighlight(point, geometry: sidebarDragGeometry.frames),
              let name = context.sectionDescriptors.first(where: { $0.id == .custom(highlight.sectionID) })?.name else {
            return nil
        }
        let sectionID = highlight.sectionID
        // Clears only its own section's outline: a second header's menu can set the next
        // highlight before this one's close arrives, and an unconditional clear would drop it.
        let handler = SidebarSecondaryClickMenuHandler(
            onDismiss: {
                if sidebarSectionSecondaryClickHighlight?.sectionID == sectionID {
                    sidebarSectionSecondaryClickHighlight = nil
                }
            }
        )
        let menu = NSMenu()
        for item in sidebarSectionContextMenuItems(isInlineEditingActive: isSidebarInlineEditingActive) {
            switch item {
            case .rename:
                menu.addItem(handler.item(titled: "Rename...") { beginSectionRename(sectionID: sectionID) })
            case .remove:
                menu.addItem(handler.item(titled: "Remove Section...") {
                    requestSectionRemoval(sectionID: sectionID, name: name)
                })
            }
        }
        guard !menu.items.isEmpty else {
            return nil
        }
        // Assigned after the items exist: the delegate reference is weak, and the items are what
        // keep the handler alive.
        menu.delegate = handler
        sidebarSectionSecondaryClickHighlight = highlight
        return menu
    }

    private func sidebarEmptyAreaMenu(at point: CGPoint) -> NSMenu? {
        guard !isSidebarInlineEditingActive,
              sidebarEmptyAreaContainsPoint(point, geometry: sidebarDragGeometry.frames) else {
            return nil
        }
        let menu = NSMenu()
        let handler = SidebarSecondaryClickMenuHandler()
        menu.addItem(handler.item(titled: "New Section...") { beginCreatingSection() })
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

/// Owns the `@objc` actions an `NSMenuItem` needs and clears the section highlight when the menu
/// closes. `SidebarView` is a struct, so it cannot be a menu-item target itself.
///
/// `NSMenu.delegate` is weak, so the menu's own items hold this through `representedObject` —
/// the only strong reference for as long as the menu is open.
@MainActor
final class SidebarSecondaryClickMenuHandler: NSObject, NSMenuDelegate {
    private let onDismiss: @MainActor () -> Void

    init(onDismiss: @escaping @MainActor () -> Void = {}) {
        self.onDismiss = onDismiss
    }

    /// A menu item wired to this handler and retaining it, with `action` stored on the item so one
    /// handler can serve a menu of several items.
    func item(titled title: String, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = SidebarSecondaryClickMenuItem(
            title: title,
            action: #selector(invoke(_:)),
            keyEquivalent: ""
        )
        item.invoke = action
        item.target = self
        item.representedObject = self
        return item
    }

    @objc
    private func invoke(_ sender: NSMenuItem) {
        (sender as? SidebarSecondaryClickMenuItem)?.invoke?()
    }

    func menuDidClose(_ menu: NSMenu) {
        onDismiss()
    }
}

/// Carries its own closure so `SidebarSecondaryClickMenuHandler` needs one `@objc` selector rather
/// than one per menu entry.
private final class SidebarSecondaryClickMenuItem: NSMenuItem {
    var invoke: (@MainActor () -> Void)?
}

/// A custom section lit by a secondary click, with the frame its outline borders.
struct SidebarSectionHighlight: Equatable {
    let sectionID: String
    /// In the drag named space, like every other published sidebar frame.
    let frame: CGRect
}

/// The custom section a secondary click landed on, or nil for any other point.
///
/// Composed from the same published geometry a drop container uses, so the outline matches what a
/// dragged thread sees: `.customSectionHeader` publishes only the visible title row — the divider
/// and its breathing room are excluded — and a collapsed section's rows unmount and stop
/// publishing `.customSectionTerminal`, leaving the header alone. The point arrives in overlay
/// coordinates and is converted exactly as `sidebarEmptyAreaContainsPoint` converts its own.
func sidebarSecondaryClickSectionHighlight(
    _ monitorPoint: CGPoint,
    geometry: [SidebarDragGeometryRole: [CGRect]]
) -> SidebarSectionHighlight? {
    guard let viewport = geometry[.viewport]?.sidebarUnion else {
        return nil
    }
    let point = sidebarDragLocationInNamedSpace(monitorLocation: monitorPoint, viewport: viewport)
    for (role, frames) in geometry {
        guard case .customSectionHeader(let sectionID) = role,
              let headerFrame = frames.sidebarUnion,
              headerFrame.contains(point) else {
            continue
        }
        return SidebarSectionHighlight(
            sectionID: sectionID,
            frame: sidebarSectionContainerFrame(
                headerFrame: headerFrame,
                contentFrames: [geometry[.customSectionTerminal(sectionID)]?.sidebarUnion].compactMap { $0 }
            )
        )
    }
    return nil
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
