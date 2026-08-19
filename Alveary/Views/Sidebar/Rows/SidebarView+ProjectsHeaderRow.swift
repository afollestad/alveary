import SwiftUI

struct SidebarSectionHeaderRow: View, Equatable {
    static let contentLeadingPadding: CGFloat = 8
    /// Leading padding that lands a plain row's ink under a header's title ink. It carries the
    /// plain-row correction because every consumer is a row rather than a `List` section header.
    static let titleInkLeadingPadding: CGFloat = contentLeadingPadding
        + titleLeadingOpticalOffset
        + SidebarProjectListMetrics.plainRowLeadingCorrection

    static let actionButtonSize: CGFloat = SidebarProjectRow.trailingActionButtonSize
    static let actionButtonCenterTrailingInset = SidebarProjectRow.trailingActionCenterTrailingInset
    // Center inline dividers within the same visual breathing room used by the native Projects boundary.
    static let inlineHeaderTopPaddingCorrection: CGFloat = 11
    /// Full leading padding above an inline header's title, including the divider's breathing room.
    /// Drag geometry excludes all of it so a section border hugs the visible header rather than
    /// floating above it.
    static let inlineHeaderTotalTopPadding = SidebarRowMetrics.pinnedThreadBoundarySpacing
        + inlineHeaderTopPaddingCorrection

    /// Matches `appSelectableRow`'s click gate, so a release still reads as a click after the
    /// small pointer drift a real click carries.
    private static let toggleClickSlop: CGFloat = 10
    private static let actionIconSize: CGFloat = 11
    private static let inlineDividerYOffset: CGFloat = 1.5
    // Keep the trailing action column fixed while pulling title ink left of the row content inset.
    private static let titleLeadingOpticalOffset: CGFloat = -3
    private static let trailingPadding = actionButtonCenterTrailingInset - actionButtonSize / 2

    @State private var isHoveringAction = false
    @State private var isHoveringRow = false
    @State private var editText = ""
    @FocusState private var isFieldFocused: Bool

    let title: String
    let actionSystemImage: String?
    let actionAccessibilityLabel: String?
    let actionHelp: String?
    // `@MainActor` so the nonisolated `==` may probe this optional's presence.
    let onAction: (@MainActor () -> Void)?
    let showsTopDivider: Bool
    let disclosure: SidebarSectionHeaderDisclosure?
    let suppressHoverAffordances: Bool
    /// Non-nil while this header is being renamed in place; the title swaps for a text field and
    /// the row stops toggling so a click inside the field cannot collapse the section.
    let editing: SidebarSectionHeaderEditing?
    /// True only while this header is collapsed over a thread waiting on the user.
    /// `sidebarWaitingAttention(...)` folds nothing for an expanded section, so the dot renders on
    /// this flag alone rather than re-reading `disclosure`.
    let hidesWaitingThread: Bool

    init(
        title: String,
        showsTopDivider: Bool = false,
        disclosure: SidebarSectionHeaderDisclosure? = nil,
        hidesWaitingThread: Bool = false,
        suppressHoverAffordances: Bool = false,
        initialRowHover: Bool = false,
        editing: SidebarSectionHeaderEditing? = nil,
        onAddProject: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        actionSystemImage = onAddProject == nil ? nil : "folder.badge.plus"
        actionAccessibilityLabel = onAddProject == nil ? nil : "Add Project"
        actionHelp = onAddProject == nil ? nil : "Add Project... (\(KeyboardShortcut.addProject.displayString))"
        onAction = onAddProject
        self.showsTopDivider = showsTopDivider
        self.disclosure = disclosure
        self.hidesWaitingThread = hidesWaitingThread
        self.suppressHoverAffordances = suppressHoverAffordances
        self.editing = editing
        _isHoveringRow = State(initialValue: initialRowHover)
    }

    init(
        title: String,
        showsTopDivider: Bool = false,
        actionSystemImage: String,
        actionAccessibilityLabel: String,
        actionHelp: String,
        disclosure: SidebarSectionHeaderDisclosure? = nil,
        hidesWaitingThread: Bool = false,
        suppressHoverAffordances: Bool = false,
        initialRowHover: Bool = false,
        onAction: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.actionSystemImage = actionSystemImage
        self.actionAccessibilityLabel = actionAccessibilityLabel
        self.actionHelp = actionHelp
        self.onAction = onAction
        self.showsTopDivider = showsTopDivider
        self.disclosure = disclosure
        self.hidesWaitingThread = hidesWaitingThread
        self.suppressHoverAffordances = suppressHoverAffordances
        editing = nil
        _isHoveringRow = State(initialValue: initialRowHover)
    }

    /// `onAction` is excluded beyond its presence — presence decides whether the trailing action
    /// button renders at all; the closure itself captures the sidebar's `@State`-backed action
    /// paths, which a kept copy reads live. `disclosure` and `editing` compare their own value
    /// halves and exclude their closures for the same reason.
    nonisolated static func == (lhs: SidebarSectionHeaderRow, rhs: SidebarSectionHeaderRow) -> Bool {
        lhs.title == rhs.title
            && lhs.actionSystemImage == rhs.actionSystemImage
            && lhs.actionAccessibilityLabel == rhs.actionAccessibilityLabel
            && lhs.actionHelp == rhs.actionHelp
            && (lhs.onAction == nil) == (rhs.onAction == nil)
            && lhs.showsTopDivider == rhs.showsTopDivider
            && lhs.disclosure == rhs.disclosure
            && lhs.hidesWaitingThread == rhs.hidesWaitingThread
            && lhs.suppressHoverAffordances == rhs.suppressHoverAffordances
            && lhs.editing == rhs.editing
    }

    /// Pulls a row-mounted header back to the leading inset a `List` section header gets for free.
    private var leadingCorrection: CGFloat {
        SidebarProjectListMetrics.plainRowLeadingCorrection
    }

    private var dividerLeadingInset: CGFloat {
        Self.contentLeadingPadding + Self.titleLeadingOpticalOffset + leadingCorrection
    }

    private var headerTopPadding: CGFloat {
        SidebarRowMetrics.pinnedThreadBoundarySpacing
            + (showsTopDivider ? Self.inlineHeaderTopPaddingCorrection : 0)
    }

    var body: some View {
        HStack {
            titleCluster

            Spacer()

            actionControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Self.contentLeadingPadding + leadingCorrection)
        .padding(.trailing, Self.trailingPadding)
        // Shaping the title row rather than the padded whole keeps the toggle on the header itself,
        // so a click in the section gap above it does nothing. This has to be the row's own content
        // shape, not a backing rectangle: `Text` hit-tests its own frame, so a background layer
        // never saw a click that landed on the title.
        .contentShape(Rectangle())
        .gesture(rowToggleGesture)
        .onHover { isHovering in
            withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
                isHoveringRow = isHovering
            }
        }
        // Seeded on appear as well as on change: a row that mounts already editing — SwiftUI
        // rebuilding this header mid-rename because the section list changed around it — gets no
        // `onChange`, and an unseeded field would silently blank the name being edited.
        .onAppear(perform: seedRenameFieldIfEditing)
        .onChange(of: editing?.isEditing ?? false) { _, isEditing in
            if isEditing {
                seedRenameFieldIfEditing()
            }
        }
        .onChange(of: isFieldFocused) { _, focused in
            if !focused, editing?.isEditing == true {
                editing?.onCommit(editText)
            }
        }
        .padding(.top, headerTopPadding)
        .padding(.bottom, 0)
        .overlay(alignment: .top) {
            if showsTopDivider {
                Divider()
                    .opacity(0.5)
                    .padding(.leading, dividerLeadingInset)
                    .padding(.trailing, Self.trailingPadding)
                    .padding(.top, SidebarRowMetrics.pinnedThreadBoundarySpacing / 2)
                    .offset(y: Self.inlineDividerYOffset)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var titleCluster: some View {
        if let editing, editing.isEditing {
            renameField(editing)
        } else {
            collapsibleTitleCluster
        }
    }

    private func seedRenameFieldIfEditing() {
        guard editing?.isEditing == true else {
            return
        }
        editText = title
        isFieldFocused = true
    }

    private func renameField(_ editing: SidebarSectionHeaderEditing) -> some View {
        TextField("Section name", text: $editText)
            .textFieldStyle(.plain)
            .font(.system(.subheadline, weight: .semibold))
            .focused($isFieldFocused)
            .onSubmit { editing.onCommit(editText) }
            .onExitCommand(perform: editing.onCancel)
            .lineLimit(1)
            .sidebarInlineSectionNameFieldChrome()
            .offset(x: Self.titleLeadingOpticalOffset)
    }

    private var collapsibleTitleCluster: some View {
        HStack(spacing: SidebarDisclosureCaretMetrics.spacing) {
            Text(title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(.tertiary)
                // Single-line like every other sidebar row. Without this a long custom section
                // name wraps to two lines and grows the header, and the trailing caret and
                // waiting dot both shrink the width that wrapping is measured against.
                .lineLimit(1)

            if let disclosure {
                SidebarDisclosureCaret(
                    isExpanded: disclosure.isExpanded,
                    isRowHovering: isHoveringRow,
                    suppressHoverAffordances: suppressHoverAffordances,
                    toggle: SidebarDisclosureCaretToggle(
                        label: toggleLabel(isExpanded: disclosure.isExpanded),
                        action: disclosure.onToggle
                    )
                )
            }

            if hidesWaitingThread {
                SidebarWaitingAttentionDot()
            }
        }
        // Offsetting the cluster rather than the title keeps the caret's gap measured from the
        // title's ink, which is what aligns it with the project rows below.
        .offset(x: Self.titleLeadingOpticalOffset)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(disclosure == nil ? .isHeader : [.isHeader, .isButton])
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var actionControl: some View {
        if let onAction, let actionSystemImage, let actionAccessibilityLabel, let actionHelp {
            Button(action: onAction) {
                Image(systemName: actionSystemImage)
                    .font(.system(size: Self.actionIconSize, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isHoveringAction ? 0.9 : 0.68))
                    .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHoveringAction ? 0.12 : 0))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { isHovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHoveringAction = isHovering
                }
            }
            .accessibilityLabel(actionAccessibilityLabel)
            .help(actionHelp)
        } else {
            Color.clear
                .frame(width: Self.actionButtonSize, height: Self.actionButtonSize)
                .accessibilityHidden(true)
        }
    }

    /// A zero-distance drag rather than `onTapGesture`, and it is load-bearing for the header's
    /// *drag* as much as for its click.
    ///
    /// `NSHostingView.mouseDown(with:)` only swallows the event when some SwiftUI gesture claims it
    /// there and then. A `TapGesture` and `sidebarDragSource`'s 3pt drag can both still fail, so
    /// the mouse-down reached `super` and walked up to `-[NSTableView mouseDown:]`, which runs its
    /// own `trackEventsMatchingMask:` loop and dequeues every later drag and mouse-up without
    /// re-dispatching them — the section drag got one update, no end, and the sidebar stayed wedged
    /// in a drag that could never finish. A zero-distance drag recognizes on mouse-down, which is
    /// what keeps the event stream in SwiftUI; `SidebarDragMonitorView.performEscapeWatchTick` is
    /// the backstop for anything that still loses the mouse-up.
    ///
    /// It also fixes the click: `onTapGesture` on macOS stops firing once a click is held past its
    /// short-click threshold, the same reason `appSelectableRow` uses this shape. The translation
    /// gate keeps a completed row drag from toggling on release.
    private var rowToggleGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard abs(value.translation.width) < Self.toggleClickSlop,
                      abs(value.translation.height) < Self.toggleClickSlop else {
                    return
                }
                toggleFromRow()
            }
    }

    /// The whole header row toggles its section. The caret and the trailing action button are
    /// children with gestures of their own, so hit testing reaches them first and each keeps taking
    /// its own clicks. A header without a disclosure has nothing to toggle and absorbs the tap.
    private func toggleFromRow() {
        guard let disclosure else {
            return
        }

        withAnimation(SidebarDisclosureCaretMetrics.toggleAnimation) {
            disclosure.onToggle()
        }
    }

    private var accessibilityLabel: String {
        let base = disclosure.map { toggleLabel(isExpanded: $0.isExpanded) } ?? title
        return sidebarWaitingAttentionAccessibilityLabel(base, hidesWaitingThread: hidesWaitingThread)
    }

    private func toggleLabel(isExpanded: Bool) -> String {
        isExpanded ? "Collapse \(title)" : "Expand \(title)"
    }
}

/// The collapse affordance a section header shows. Absent on `Pinned`, which heads a group the user
/// does not choose to hide.
struct SidebarSectionHeaderDisclosure: Equatable {
    let isExpanded: Bool
    // `@MainActor` keeps the struct `Sendable` for the header row's nonisolated `==`.
    let onToggle: @MainActor () -> Void

    /// `onToggle` is excluded: it captures the section's stable identity plus the sidebar's
    /// `@State` collapse storage, which a kept copy reads live.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isExpanded == rhs.isExpanded
    }
}

/// Inline-rename state for a custom section's header. Only custom sections pass one; built-in
/// names are fixed.
struct SidebarSectionHeaderEditing: Equatable {
    let isEditing: Bool
    // `@MainActor` keeps the struct `Sendable` for the header row's nonisolated `==`.
    let onCommit: @MainActor (String) -> Void
    let onCancel: @MainActor () -> Void

    /// The closures are excluded: both capture the section's stable identity plus the sidebar's
    /// `@State`-backed rename paths, which a kept copy reads live.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isEditing == rhs.isEditing
    }
}
