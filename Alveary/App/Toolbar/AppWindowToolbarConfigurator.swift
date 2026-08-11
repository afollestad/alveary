@preconcurrency import AppKit
import SwiftUI

enum MainWindowToolbarItemID {
    static let header = "main-pane-header"
    static let actions = "main-pane-actions"
}

enum MainWindowToolbarSpacerPlacement {
    static func move(
        in identifiers: [NSToolbarItem.Identifier]
    ) -> (removeIndex: Int, insertIndex: Int)? {
        guard let spacerIndex = identifiers.firstIndex(of: .flexibleSpace),
              let headerIndex = identifiers.firstIndex(of: .init(MainWindowToolbarItemID.header)),
              let actionsIndex = identifiers.firstIndex(of: .init(MainWindowToolbarItemID.actions)),
              headerIndex < actionsIndex else {
            return nil
        }

        guard spacerIndex + 1 != actionsIndex || spacerIndex < headerIndex else {
            return nil
        }

        let insertIndex = actionsIndex - (spacerIndex < actionsIndex ? 1 : 0)
        return (spacerIndex, insertIndex)
    }
}

/// Applies the app's window-toolbar policy.
///
/// Keeps SwiftUI's flexible spacer between the two app-owned toolbar items —
/// `NavigationSplitView` otherwise places the spacer before its system items,
/// leaving the contextual header and primary actions packed together — and
/// keeps the toolbar out of the user's hands, because app-owned items draw
/// their own capsule chrome and labels that the system display-mode options
/// would break.
struct AppWindowToolbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> AppWindowToolbarAnchorView {
        AppWindowToolbarAnchorView()
    }

    func updateNSView(_ nsView: AppWindowToolbarAnchorView, context: Context) {
        nsView.scheduleUpdate()
    }
}

extension View {
    func appWindowChromeConfigured() -> some View {
        background {
            AppWindowTitlebarSeparatorConfigurator(style: .none)
                .frame(width: 0, height: 0)
        }
        .background {
            AppWindowToolbarConfigurator()
                .frame(width: 0, height: 0)
        }
    }
}

final class AppWindowToolbarAnchorView: NSView {
    private weak var observedToolbar: NSToolbar?
    private var isUpdateScheduled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeToolbarIfNeeded()
        scheduleUpdate()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func scheduleUpdate() {
        guard !isUpdateScheduled else {
            return
        }

        isUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isUpdateScheduled = false
            observeToolbarIfNeeded()
            disableToolbarCustomization()
            moveFlexibleSpacerBetweenAppItems()
        }
    }

    private func observeToolbarIfNeeded() {
        guard let toolbar = window?.toolbar,
              observedToolbar !== toolbar else {
            return
        }

        observedToolbar = toolbar

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(toolbarItemsChanged),
            name: NSToolbar.willAddItemNotification,
            object: toolbar
        )
        center.addObserver(
            self,
            selector: #selector(toolbarItemsChanged),
            name: NSToolbar.didRemoveItemNotification,
            object: toolbar
        )
    }

    @objc private func toolbarItemsChanged(_: Notification) {
        scheduleUpdate()
    }

    /// Clearing both flags leaves the toolbar's context menu empty, which is how
    /// AppKit is told not to show it at all.
    private func disableToolbarCustomization() {
        guard let toolbar = window?.toolbar else {
            return
        }

        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false

        // A toolbar restored from an earlier customization can come back in a
        // label-showing mode, so put the intended mode back.
        if toolbar.displayMode != .iconOnly {
            toolbar.displayMode = .iconOnly
        }
    }

    private func moveFlexibleSpacerBetweenAppItems() {
        guard let toolbar = window?.toolbar else {
            return
        }

        guard let move = MainWindowToolbarSpacerPlacement.move(
            in: toolbar.items.map(\.itemIdentifier)
        ) else {
            return
        }

        toolbar.removeItem(at: move.removeIndex)
        toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: move.insertIndex)
    }
}
