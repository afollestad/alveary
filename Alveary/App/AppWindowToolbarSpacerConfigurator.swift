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

/// Keeps SwiftUI's flexible spacer between the two app-owned toolbar items.
/// `NavigationSplitView` otherwise places the spacer before its system items,
/// leaving the contextual header and primary actions packed together.
struct AppWindowToolbarSpacerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> AppWindowToolbarSpacerAnchorView {
        AppWindowToolbarSpacerAnchorView()
    }

    func updateNSView(_ nsView: AppWindowToolbarSpacerAnchorView, context: Context) {
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
            AppWindowToolbarSpacerConfigurator()
                .frame(width: 0, height: 0)
        }
    }
}

final class AppWindowToolbarSpacerAnchorView: NSView {
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
