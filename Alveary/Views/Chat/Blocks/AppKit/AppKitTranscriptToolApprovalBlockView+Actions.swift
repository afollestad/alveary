import AppKit

@MainActor
extension AppKitTranscriptToolApprovalBlockView {
    func updateApprovalSplitControl(scopes: [ToolApprovalSessionScope]) {
        let title = pendingApprovalMenuTitle(for: selectedApprovalSelection, scopes: scopes)
        approvalSplitControl.setLabel(title, forSegment: 0)
        approvalSplitControl.setImage(NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil), forSegment: 0)
        approvalSplitControl.setImage(NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil), forSegment: 1)
        approvalSplitControl.setAccessibilityLabel(title)
        approvalSplitControl.menu = approvalSelectionMenu(scopes: scopes)
        sizeApprovalSplitControl()
    }

    func sizeApprovalSplitControl() {
        approvalSplitControl.setWidth(max(approvalSplitControl.preferredContentWidth, 94), forSegment: 0)
        approvalSplitControl.setWidth(AppKitTranscriptApprovalSplitControl.menuWidth, forSegment: 1)
        approvalSplitControl.frame.size = approvalSplitControl.fittingSize
    }

    func actionState(for configuration: Configuration, scopes: [ToolApprovalSessionScope]) -> ApprovalActionState {
        let actionsAreDisabled = configuration.status != .pending || configuration.isBlocked
        switch configuration.status {
        case .denying, .denied:
            return deniedState(for: configuration, scopes: scopes)
        case .superseded:
            return supersededState(for: configuration)
        case .approving, .approved:
            return resolvedApproveState(title: configuration.approval.approvalPromptCopy.approvedTitle, symbol: "checkmark")
        case .approvingForSessionExact, .approvedForSessionExact:
            let title = scopes.count == 1 ? "Approved for session" : ToolApprovalSessionScope.exact.resolvedTitle
            return resolvedApproveState(title: title, symbol: "clock.badge.checkmark")
        case .approvingForSessionGroup, .approvedForSessionGroup:
            return resolvedApproveState(title: ToolApprovalSessionScope.group.resolvedTitle, symbol: "clock.badge.checkmark")
        case .pending:
            return pendingState(for: configuration, scopes: scopes, actionsAreDisabled: actionsAreDisabled)
        case nil:
            return pendingState(for: configuration, scopes: scopes, actionsAreDisabled: true)
        }
    }

    func pendingApprovalTitle(for configuration: Configuration, scopes: [ToolApprovalSessionScope]) -> String {
        if scopes.isEmpty {
            return configuration.approval.approvalPromptCopy.approveTitle
        }
        return pendingApprovalMenuTitle(for: selectedApprovalSelection, scopes: scopes)
    }

    func pendingApprovalMenuTitle(for selection: ToolApprovalSelection, scopes: [ToolApprovalSessionScope]) -> String {
        switch selection.normalized(for: scopes) {
        case .once:
            return "Approve once"
        case .sessionExact, .sessionGroup:
            guard let scope = selection.sessionScope else {
                return "Approve for session"
            }
            return scopes.count == 1 ? "Approve for session" : scope.pendingTitle
        }
    }

    func sessionApprovalScopes(for configuration: Configuration) -> [ToolApprovalSessionScope] {
        let allApprovalScopes = configuration.approvals.map { Set($0.supportedSessionApprovalScopes) }
        guard !allApprovalScopes.isEmpty else {
            return configuration.approval.supportedSessionApprovalScopes
        }
        return configuration.approval.supportedSessionApprovalScopes.filter { scope in
            allApprovalScopes.allSatisfy { $0.contains(scope) }
        }
    }

    func summaryItems(for configuration: Configuration) -> [AppKitTranscriptApprovalSummaryItem] {
        configuration.approvals.compactMap { approval in
            guard let summary = approval.transcriptApprovalSummary else {
                return nil
            }
            return AppKitTranscriptApprovalSummaryItem(summary: summary, isCommand: approval.toolName == "Bash")
        }
    }

    @objc func handleApprove() {
        guard let configuration, configuration.status == .pending, !configuration.isBlocked else {
            return
        }
        if let scope = selectedApprovalSelection.normalized(for: sessionApprovalScopes(for: configuration)).sessionScope {
            onApproveForSession?(scope)
        } else {
            onApprove?()
        }
    }

    @objc func handleDeny() {
        guard let configuration, configuration.status == .pending, !configuration.isBlocked else {
            return
        }
        onDeny?()
    }

    @objc func handleApprovalSplitControl() {
        switch approvalSplitControl.selectedSegment {
        case 0:
            handleApprove()
        case 1:
            showApprovalSelectionMenu()
        default:
            break
        }
    }

    private func approvalSelectionMenu(scopes: [ToolApprovalSessionScope]) -> NSMenu {
        let menu = NSMenu()
        let selections = [.once] + scopes.map(ToolApprovalSelection.init(sessionScope:))
        for selection in selections {
            let item = NSMenuItem(
                title: pendingApprovalMenuTitle(for: selection, scopes: scopes),
                action: #selector(handleApprovalSelectionMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = selection.rawValue
            item.state = selection.normalized(for: scopes) == selectedApprovalSelection.normalized(for: scopes) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func showApprovalSelectionMenu() {
        guard let configuration else {
            return
        }
        let menu = approvalSelectionMenu(scopes: sessionApprovalScopes(for: configuration))
        let origin = NSPoint(x: approvalSplitControl.frame.maxX - 28, y: approvalSplitControl.frame.maxY + 2)
        menu.popUp(positioning: nil, at: origin, in: bubbleView)
    }

    @objc private func handleApprovalSelectionMenuItem(_ item: NSMenuItem) {
        guard let rawValue = item.representedObject as? String,
              let selection = ToolApprovalSelection(rawValue: rawValue),
              let configuration else {
            return
        }
        selectApprovalSelection(selection, configuration: configuration)
    }

    private func selectApprovalSelection(_ selection: ToolApprovalSelection, configuration: Configuration) {
        selectedApprovalSelection = selection.normalized(for: sessionApprovalScopes(for: configuration))
        approveButton.title = pendingApprovalTitle(for: configuration, scopes: sessionApprovalScopes(for: configuration))
        updateApprovalSplitControl(scopes: sessionApprovalScopes(for: configuration))
        onSelectApprovalSelection?(selectedApprovalSelection)
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    private func deniedState(for configuration: Configuration, scopes: [ToolApprovalSessionScope]) -> ApprovalActionState {
        ApprovalActionState(
            approveTitle: pendingApprovalTitle(for: configuration, scopes: scopes),
            approveSymbol: "checkmark",
            approveEnabled: false,
            approvePlaceholder: true,
            denyTitle: configuration.approval.approvalPromptCopy.deniedTitle,
            denySymbol: "xmark",
            denyEnabled: false,
            showSplitApproval: !scopes.isEmpty,
            showDenyInPrimarySlot: true
        )
    }

    private func supersededState(for configuration: Configuration) -> ApprovalActionState {
        ApprovalActionState(
            approveTitle: "Superseded",
            approveSymbol: "arrow.trianglehead.clockwise",
            approveEnabled: false,
            denyTitle: configuration.approval.approvalPromptCopy.denyTitle,
            denySymbol: "xmark",
            denyEnabled: false,
            denyPlaceholder: true
        )
    }

    private func pendingState(
        for configuration: Configuration,
        scopes: [ToolApprovalSessionScope],
        actionsAreDisabled: Bool
    ) -> ApprovalActionState {
        ApprovalActionState(
            approveTitle: pendingApprovalTitle(for: configuration, scopes: scopes),
            approveSymbol: "checkmark",
            approveEnabled: !actionsAreDisabled,
            denyTitle: configuration.approval.approvalPromptCopy.denyTitle,
            denySymbol: "xmark",
            denyEnabled: !actionsAreDisabled,
            showSplitApproval: !scopes.isEmpty
        )
    }

    private func resolvedApproveState(title: String, symbol: String) -> ApprovalActionState {
        ApprovalActionState(
            approveTitle: title,
            approveSymbol: symbol,
            approveEnabled: false,
            denyTitle: configuration?.approval.approvalPromptCopy.denyTitle ?? "Deny",
            denySymbol: "xmark",
            denyEnabled: false,
            denyPlaceholder: true
        )
    }
}

extension AppKitTranscriptToolApprovalBlockView {
    struct ApprovalActionState {
        let approveTitle: String
        let approveSymbol: String
        let approveEnabled: Bool
        var approvePlaceholder = false
        let denyTitle: String
        let denySymbol: String
        let denyEnabled: Bool
        var denyPlaceholder = false
        var showSplitApproval = false
        var showDenyInPrimarySlot = false
    }
}
