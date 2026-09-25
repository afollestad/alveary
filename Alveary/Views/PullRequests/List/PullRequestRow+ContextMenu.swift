import AppKit
import SwiftData
import SwiftUI

/// A list row's right-click menu. SwiftUI evaluates `contextMenu` content when the menu opens,
/// not with the row, so the linked threads come from a fresh fetch: the screen's `@Query` result
/// is captured per body pass, and an equatable row that skipped a pass would carry a stale or
/// deleted snapshot into its menu.
///
/// There are no state changes (Close, Reopen, Draft): each needs the detail's `viewerCanUpdate`
/// and node id, which a list row does not have.
struct PullRequestRowContextMenu: View {
    let model: PullRequestRowModel
    let reviewMode: PullRequestReviewMode
    let onStartAgenticThread: (PullRequestAgenticThreadService.Kind) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.pullRequestLinkedOwnerOpenAction) private var openOwner

    private var summary: PullRequestSummary { model.summary }

    private var url: URL? { summary.url ?? summary.id.webURL }

    var body: some View {
        if let url {
            Button {
                UIApplicationShim.open(url: url)
            } label: {
                menuLabel("Open on GitHub", icon: .system("arrow.up.right.square"))
            }
        }
        if model.hasLinkedThread, let openOwner {
            linkedThreadItems(openOwner: openOwner)
        }

        Divider()

        agenticItem(.agenticReview, route: .review)
        agenticItem(.addressFeedback, route: .addressFeedback)

        Divider()

        if let url {
            Button {
                copyToPasteboard(url.absoluteString)
            } label: {
                menuLabel("Copy link", icon: .system("link"))
            }
        }
        Button {
            copyToPasteboard(summary.headRefName)
        } label: {
            menuLabel("Copy branch name", icon: .octicon(.gitBranch16))
        }
    }

    /// One thread opens directly; several get a submenu naming each.
    @ViewBuilder
    private func linkedThreadItems(openOwner: PullRequestLinkedOwnerOpenAction) -> some View {
        // Names are read here, while the freshly fetched rows are known live.
        let threads = PullRequestLinkedOwnerLookup.threads(linking: summary.id, in: modelContext)
            .map(PullRequestRowLinkedThread.init)
        let label = menuLabel("Open linked thread", icon: .system("bubble.left.and.bubble.right"))
        if threads.count == 1, let thread = threads.first {
            Button {
                openOwner(.thread(thread.id))
            } label: {
                label
            }
        } else if threads.count > 1 {
            Menu {
                ForEach(threads) { thread in
                    Button(thread.displayName) {
                        openOwner(.thread(thread.id))
                    }
                }
            } label: {
                label
            }
        }
    }

    /// Disabled while its route runs, matching the tracker's one-run-per-route guard.
    private func agenticItem(
        _ action: PullRequestReviewFooterAction.Kind,
        route: PullRequestAgenticThreadService.Kind
    ) -> some View {
        Button {
            onStartAgenticThread(route)
        } label: {
            menuLabel(
                PullRequestReviewFooterAction.title(for: action, reviewMode: reviewMode),
                icon: PullRequestReviewFooterAction.action(for: action).icon
            )
        }
        .disabled(model.workingAgenticKinds.contains(route))
    }

    private func menuLabel(_ title: String, icon: ActionIcon) -> some View {
        Label {
            Text(title)
        } icon: {
            // Menu rows sit at the system menu font, matching `DiffBranchSelectionMenu`'s rows.
            ActionIconImage(icon: icon, octiconSize: 16)
        }
        .labelStyle(.titleAndIcon)
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct PullRequestRowLinkedThread: Identifiable {
    let id: PersistentIdentifier
    let displayName: String

    init(_ thread: AgentThread) {
        id = thread.persistentModelID
        displayName = thread.displayName()
    }
}
