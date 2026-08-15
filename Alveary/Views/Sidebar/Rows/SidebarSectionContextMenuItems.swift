import SwiftUI

/// What a custom section header's context menu offers. Built-in sections get no menu at all —
/// their names are fixed and they cannot be removed.
enum SidebarSectionContextMenuItem: Equatable {
    case rename
    case remove
}

/// Rename is withheld while any inline edit is in flight, matching the thread-rename gate:
/// swapping the editing target mid-edit strands the previous row without an input field, because
/// the `TextField` unmount and mount inside one SwiftUI update pass do not converge.
func sidebarSectionContextMenuItems(isInlineEditingActive: Bool) -> [SidebarSectionContextMenuItem] {
    isInlineEditingActive ? [.remove] : [.rename, .remove]
}

/// The section a pending removal targets. A value type rather than the model, so the dialog can
/// name a section that has since been deleted without reading a dead row.
struct SidebarPendingSectionRemoval: Identifiable, Equatable {
    let id: String
    let name: String
}
