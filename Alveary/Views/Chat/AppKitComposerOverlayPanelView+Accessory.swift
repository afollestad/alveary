@preconcurrency import AppKit

private typealias Metrics = AppKitComposerOverlayMetrics

extension AppKitComposerOverlayPanelView {
    func configureAccessory(_ accessory: AppKitComposerOverlayAccessory?) {
        guard let accessory else {
            accessoryMenuPresenter.close()
            accessoryButton.isHidden = true
            accessoryButton.frame = .zero
            return
        }

        accessoryButton.isHidden = false
        if !isAccessoryEnabled(accessory) {
            accessoryMenuPresenter.close()
        }
        applyAccessoryButtonConfiguration(accessory, selection: accessoryDisplaySelectionOverride)
        // A live menu must track configuration updates, or a model picked in it would keep offering
        // the previous selection until the popover is reopened.
        if accessoryMenuPresenter.isShown {
            accessoryMenuPresenter.update(configuration: accessory.reasoning)
        }
    }

    func toggleAccessoryMenu() {
        guard let accessory = configuration?.accessory,
              isAccessoryEnabled(accessory) else {
            accessoryMenuPresenter.close()
            return
        }
        accessoryMenuPresenter.toggle(
            configuration: accessory.reasoning,
            anchorView: self,
            anchorRect: accessoryButton.convert(accessoryButton.bounds, to: self)
        )
    }

    func applyAccessoryDisplaySelectionOverride(_ selection: ChatComposerActionRowView.ReasoningSelection?) {
        accessoryDisplaySelectionOverride = selection
        guard let accessory = configuration?.accessory else {
            return
        }
        applyAccessoryButtonConfiguration(accessory, selection: selection)
        needsLayout = true
    }

    /// One enablement rule for the button, the key-view loop, and programmatic/accessibility
    /// activation — a resolving overlay must not be able to open the menu by any route.
    func isAccessoryEnabled(_ accessory: AppKitComposerOverlayAccessory) -> Bool {
        accessory.isEnabled && !(configuration?.isResolving ?? false)
    }

    private func applyAccessoryButtonConfiguration(
        _ accessory: AppKitComposerOverlayAccessory,
        selection: ChatComposerActionRowView.ReasoningSelection?
    ) {
        accessoryButton.configure(
            selection: selection ?? accessory.selection,
            height: Metrics.buttonHeight,
            isEnabled: isAccessoryEnabled(accessory),
            showsProgress: false,
            actionHandler: { [weak self] in
                self?.toggleAccessoryMenu()
            }
        )
    }

    /// Width the accessory adds to the trailing footer group: the button plus its gap before Dismiss.
    var accessoryFooterWidth: CGFloat {
        guard !accessoryButton.isHidden else {
            return 0
        }
        return accessoryButton.intrinsicContentSize.width + Metrics.footerButtonSpacing
    }

    /// Sits immediately left of Dismiss so the footer reads as one trailing action group. Requires
    /// `dismissButton.frame` to be laid out first.
    func layoutAccessory(footerY: CGFloat) {
        guard !accessoryButton.isHidden else {
            accessoryButton.frame = .zero
            return
        }
        let size = accessoryButton.intrinsicContentSize
        accessoryButton.frame = NSRect(
            x: dismissButton.frame.minX - Metrics.footerButtonSpacing - size.width,
            y: footerY + floor((Metrics.buttonHeight - size.height) / 2),
            width: size.width,
            height: size.height
        )
    }
}
