import AppKit

extension AppKitTranscriptRowFactory {
    func layoutRows(
        for visualRow: AppKitTranscriptVisualRow,
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        switch visualRow {
        case .item(let item):
            return layoutRows(for: item, configuration: configuration)
        case .activityGroup(let id, let children):
            return [activityGroupRow(id: id, children: children, configuration: configuration)]
        }
    }

    func activityGroupRow(
        id: String,
        children: [AppKitTranscriptActivityChild],
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptActivityGroupView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onUserInitiatedHeightChange = configuration.onUserInitiatedHeightChange
        view.onOpenMarkdownLink = configuration.onOpenMarkdownLink
        view.onOpenMarkdownImage = configuration.onOpenMarkdownImage
        view.onOpenToolImage = configuration.onOpenToolImage
        view.onExpansionChanged = { expanded in
            configuration.onRowExpansionChanged(id, expanded)
        }
        view.onChildExpansionChanged = { childID, expanded in
            configuration.onRowExpansionChanged(childID, expanded)
        }

        let childExpansionIDs = Set(children.compactMap(\.expansionID))
        view.configure(
            .init(
                children: children,
                initiallyExpanded: configuration.expandedRowIDs.contains(id) ||
                    !configuration.expandedRowIDs.isDisjoint(with: childExpansionIDs),
                expandedChildIDs: configuration.expandedRowIDs.intersection(childExpansionIDs),
                maxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }
}
