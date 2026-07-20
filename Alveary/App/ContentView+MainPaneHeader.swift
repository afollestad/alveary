import SwiftUI

enum MainPaneToolbarLayout {
    // SwiftUI/AppKit contribute these visible edge insets before app padding.
    // Complete them to the transcript row grid instead of duplicating that grid.
    static let systemLeadingContentInset: CGFloat = 4
    static let systemTrailingContentInset: CGFloat = 10

    static let leadingPadding = transcriptScrollLeadingInset - systemLeadingContentInset
    static let trailingPadding = transcriptScrollTrailingInset - systemTrailingContentInset
}

enum MainPaneHeaderTitle: Equatable {
    case plain(String)
    case markdown(String)

    var accessibilityLabel: String {
        switch self {
        case .plain(let title):
            title
        case .markdown(let title):
            AppMarkdownInlineLabel.plainText(from: title)
        }
    }
}

struct MainPaneHeaderPresentation: Equatable {
    let title: MainPaneHeaderTitle
    let showsNewConversationButton: Bool

    init(selection: SidebarItem?) {
        switch selection {
        case .skills:
            title = .plain("Skills")
            showsNewConversationButton = false
        case .mcp:
            title = .plain("MCP")
            showsNewConversationButton = false
        case .scheduled:
            title = .plain("Scheduled")
            showsNewConversationButton = false
        case .project(let project):
            title = .plain(project.name)
            showsNewConversationButton = false
        case .thread(let thread):
            title = .markdown(thread.displayName())
            showsNewConversationButton = thread.hasCompletedInitialSetup
        case .settings:
            title = .plain("Settings")
            showsNewConversationButton = false
        case nil:
            title = .plain("Alveary")
            showsNewConversationButton = false
        }
    }
}

struct MainPaneToolbarHeader: View {
    private static let titleMaxWidth: CGFloat = 360

    let presentation: MainPaneHeaderPresentation
    let onNewConversation: (() -> Void)?

    var body: some View {
        HStack(spacing: PrimaryToolbarMetrics.buttonSpacing) {
            title
                .frame(maxWidth: Self.titleMaxWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(0)

            if presentation.showsNewConversationButton {
                Button {
                    onNewConversation?()
                } label: {
                    Label("New Conversation", systemImage: "plus")
                        .labelStyle(.iconOnly)
                }
                .primaryToolbarIconButtonStyle(imageScale: .small)
                .disabled(onNewConversation == nil)
                .blockedCursorOverlay(when: onNewConversation == nil)
                .help("New Conversation (\(KeyboardShortcut.newConversation.displayString))")
                .accessibilityLabel("New Conversation")
                .fixedSize()
                .layoutPriority(1)
            }
        }
    }

    @ViewBuilder
    private var title: some View {
        Group {
            switch presentation.title {
            case .plain(let title):
                Text(title)
                    .font(.title3)
            case .markdown(let title):
                AppMarkdownInlineLabel(text: title, textStyle: .title3)
            }
        }
        .fontWeight(.semibold)
        .lineLimit(1)
        .truncationMode(.tail)
        .clipped()
        .accessibilityLabel(presentation.title.accessibilityLabel)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ContentView {
    var headerNewConversationAction: (() -> Void)? {
        guard let newConversationAction else {
            return nil
        }

        return {
            performAppNavigationIfModelPreparationModalAbsent(
                lifecycleController: voiceInputLifecycleController,
                operation: newConversationAction
            )
        }
    }
}
