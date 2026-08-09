#if DEBUG
import Foundation
import SwiftData

/// Inserts the whole demo dataset into a freshly wiped store.
///
/// Everything the UI shows is `@Query`-driven off `modelContainer.mainContext`, so seeding that
/// context populates the sidebar, transcripts, scheduled tasks, and pull-request links at once.
/// No provider runtime is involved: transcripts render purely from `ConversationEventRecord` rows.
@MainActor
enum DemoDataSeeder {
    static func seed(into context: ModelContext, attachmentsDirectory: URL) throws {
        // Defense in depth atop the wipe-on-launch storage profile: never double-seed.
        guard try context.fetchCount(FetchDescriptor<Project>()) == 0 else {
            return
        }

        let projects = insertProjects(into: context)
        insertProjectThreads(projects: projects, attachmentsDirectory: attachmentsDirectory, into: context)
        let reviewThreads = insertTaskThreads(into: context)
        insertScheduledTasks(projects: projects, reviewThreads: reviewThreads, into: context)

        try context.save()
        // A safety net rather than a fix-up: it renumbers visible order fields dense to
        // `0..<count`, so a seeded value that drifts from the sidebar rules is corrected here
        // instead of rendering wrong.
        if try SidebarOrderNormalization.normalize(in: context) {
            try context.save()
        }
    }

    // MARK: Projects

    struct DemoProjects {
        let waypoint: Project
        let ledger: Project
        let hummingbird: Project
        let docsSite: Project
    }

    private static func insertProjects(into context: ModelContext) -> DemoProjects {
        let waypoint = Project(
            path: DemoData.waypointPath,
            name: "Waypoint",
            gitRemote: "git@github.com:demo/waypoint.git",
            remoteName: "origin",
            gitBranch: "main",
            baseRef: "main",
            githubRepository: "demo/waypoint",
            githubConnected: true,
            isPinned: true,
            pinnedSortOrder: 0
        )
        let ledger = Project(
            path: DemoData.ledgerPath,
            name: "Ledger",
            gitRemote: "git@github.com:demo/ledger.git",
            remoteName: "origin",
            gitBranch: "main",
            baseRef: "main",
            githubRepository: "demo/ledger",
            githubConnected: true,
            sidebarSortOrder: 0
        )
        let hummingbird = Project(
            path: DemoData.hummingbirdPath,
            name: "Hummingbird",
            gitRemote: "git@github.com:demo/hummingbird.git",
            remoteName: "origin",
            gitBranch: "main",
            baseRef: "main",
            githubRepository: "demo/hummingbird",
            githubConnected: true,
            sidebarSortOrder: 1
        )
        // Deliberately not a Git repository and deliberately thread-less: one project renders the
        // empty-project state, and its diff pane renders "Git features unavailable".
        let docsSite = Project(path: DemoData.docsSitePath, name: "docs-site", sidebarSortOrder: 2)

        [waypoint, ledger, hummingbird, docsSite].forEach(context.insert)
        waypoint.linkedPullRequests = [link(DemoPullRequestFixtures.tileCaching, at: DemoData.hoursAgo(20))]
        return DemoProjects(waypoint: waypoint, ledger: ledger, hummingbird: hummingbird, docsSite: docsSite)
    }

    // MARK: Project threads

    private static func insertProjectThreads(
        projects: DemoProjects,
        attachmentsDirectory: URL,
        into context: ModelContext
    ) {
        insertTripSharingThread(
            project: projects.waypoint,
            attachmentsDirectory: attachmentsDirectory,
            into: context
        )
        insertFlakyMapTestsThread(project: projects.waypoint, into: context)
        insertOnboardingThread(project: projects.waypoint, into: context)
        insertArchivedThread(project: projects.waypoint, into: context)
        insertStructuredLoggingThread(project: projects.ledger, into: context)
        insertRateLimitThread(project: projects.ledger, into: context)
        insertEmptyStatesThread(
            project: projects.hummingbird,
            attachmentsDirectory: attachmentsDirectory,
            into: context
        )
    }

    /// The flagship: a worktree thread with two conversations, a busy status dot, and the diff
    /// pane's canned workspace. Diff routing resolves `worktreePath` ahead of the project path,
    /// so this is the path `DemoGitService` keys its richest workspace on.
    private static func insertTripSharingThread(
        project: Project,
        attachmentsDirectory: URL,
        into context: ModelContext
    ) {
        let thread = makeThread(name: "Add trip sharing", project: project, modifiedAt: DemoData.minutesAgo(1))
        thread.useWorktree = true
        thread.branch = DemoData.tripSharingBranch
        thread.worktreePath = DemoData.tripSharingWorktreePath
        context.insert(thread)

        let main = makeConversation(id: DemoData.tripSharingConversation, thread: thread, into: context)
        let side = makeConversation(
            id: DemoData.tripSharingSideConversation,
            thread: thread,
            title: "Revocation shape",
            isMain: false,
            displayOrder: 1,
            into: context
        )
        seedTripSharingTranscript(
            main,
            design: prepareAttachments(
                tripSharingDesignAttachmentRequest,
                conversationID: main.id,
                attachmentsDirectory: attachmentsDirectory
            ),
            capture: prepareAttachments(
                tripSharingCaptureAttachmentRequest,
                conversationID: main.id,
                attachmentsDirectory: attachmentsDirectory
            ),
            into: context
        )
        seedTripSharingSideTranscript(side, into: context)
    }

    private static func insertFlakyMapTestsThread(project: Project, into context: ModelContext) {
        let thread = makeThread(name: "Fix flaky map tests", project: project, modifiedAt: DemoData.minutesAgo(6))
        context.insert(thread)
        let conversation = makeConversation(id: DemoData.flakyMapTestsConversation, thread: thread, into: context)
        seedFlakyMapTestsTranscript(conversation, into: context)
    }

    private static func insertOnboardingThread(project: Project, into context: ModelContext) {
        let thread = makeThread(name: "Refactor onboarding flow", project: project, modifiedAt: DemoData.hoursAgo(2))
        context.insert(thread)
        let conversation = makeConversation(
            id: DemoData.onboardingConversation,
            thread: thread,
            isUnread: true,
            into: context
        )
        let anchor = seedOnboardingTranscript(conversation, into: context)
        thread.linkedPullRequests = [link(DemoPullRequestFixtures.onboardingWalkthrough, at: DemoData.hoursAgo(3))]
        // The link prompt anchors to a message id, and is filtered out once its pull request is
        // linked — so it deliberately names a different one than the link above.
        thread.pendingPullRequestLinkPrompts = [
            PendingPullRequestPrompt(
                identifier: DemoPullRequestFixtures.searchEmptyState,
                messageEventID: anchor.id,
                conversationID: conversation.id,
                createdAt: DemoData.hoursAgo(2)
            )
        ]
    }

    /// Without at least one archived thread the sidebar's Archived row is absent, not empty — an
    /// existence probe gates it — which also changes the sidebar's trailing spacing.
    private static func insertArchivedThread(project: Project, into context: ModelContext) {
        let thread = makeThread(name: "Spike: local vector search", project: project, modifiedAt: DemoData.daysAgo(12))
        thread.archivedAt = DemoData.daysAgo(11)
        context.insert(thread)
        let conversation = makeConversation(id: DemoData.archivedConversation, thread: thread, into: context)
        seedArchivedTranscript(conversation, into: context)
    }

    private static func insertStructuredLoggingThread(project: Project, into context: ModelContext) {
        let thread = makeThread(name: "Migrate to structured logging", project: project, modifiedAt: DemoData.hoursAgo(5))
        context.insert(thread)
        let conversation = makeConversation(
            id: DemoData.structuredLoggingConversation,
            thread: thread,
            provider: "codex",
            into: context
        )
        seedStructuredLoggingTranscript(conversation, into: context)
    }

    private static func insertRateLimitThread(project: Project, into context: ModelContext) {
        let thread = makeThread(name: "Rate limit middleware", project: project, modifiedAt: DemoData.daysAgo(2))
        context.insert(thread)
        let conversation = makeConversation(id: DemoData.rateLimitConversation, thread: thread, into: context)
        seedRateLimitTranscript(conversation, into: context)
        thread.linkedPullRequests = [link(DemoPullRequestFixtures.rateLimitMiddleware, at: DemoData.daysAgo(6))]
    }

    private static func insertEmptyStatesThread(
        project: Project,
        attachmentsDirectory: URL,
        into context: ModelContext
    ) {
        let thread = makeThread(name: "Polish empty states", project: project, modifiedAt: DemoData.hoursAgo(8))
        context.insert(thread)
        let conversation = makeConversation(id: DemoData.emptyStatesConversation, thread: thread, into: context)
        seedEmptyStatesTranscript(
            conversation,
            design: prepareAttachments(
                emptyStatesDesignAttachmentRequest,
                conversationID: conversation.id,
                attachmentsDirectory: attachmentsDirectory
            ),
            capture: prepareAttachments(
                emptyStatesCaptureAttachmentRequest,
                conversationID: conversation.id,
                attachmentsDirectory: attachmentsDirectory
            ),
            into: context
        )
    }

    // MARK: Task threads

    /// The two threads the hero scheduled task fans out to, returned so its runs can attach.
    struct DemoReviewThreads {
        let waypoint: AgentThread
        let ledger: AgentThread
    }

    private static func insertTaskThreads(into context: ModelContext) -> DemoReviewThreads {
        let weekly = makeTaskThread(
            name: "Summarize weekly PRs",
            workspace: DemoData.weeklyPullRequestsWorkspace,
            modifiedAt: DemoData.minutesAgo(48),
            into: context
        )
        weekly.isPinned = true
        weekly.pinnedSortOrder = 1
        let weeklyConversation = makeConversation(
            id: DemoData.weeklyPullRequestsConversation,
            thread: weekly,
            into: context
        )
        seedWeeklyPullRequestsTranscript(weeklyConversation, into: context)

        let triage = makeTaskThread(
            name: "Triage crash reports",
            workspace: DemoData.crashTriageWorkspace,
            modifiedAt: DemoData.hoursAgo(20),
            into: context
        )
        let triageConversation = makeConversation(id: DemoData.crashTriageConversation, thread: triage, into: context)
        seedCrashTriageTranscript(triageConversation, into: context)

        return DemoReviewThreads(
            waypoint: insertReviewThread(
                .waypointTileCaching,
                modifiedAt: DemoData.hoursAgo(6),
                into: context
            ),
            ledger: insertReviewThread(
                .ledgerWebhookRetries,
                modifiedAt: DemoData.hoursAgo(6).addingTimeInterval(-4 * 60),
                into: context
            )
        )
    }

    private static func insertReviewThread(
        _ proposal: DemoReviewProposal,
        modifiedAt: Date,
        into context: ModelContext
    ) -> AgentThread {
        let thread = makeTaskThread(
            name: proposal.threadName,
            workspace: proposal.workspace,
            modifiedAt: modifiedAt,
            into: context
        )
        let conversation = makeConversation(id: proposal.conversationID, thread: thread, into: context)
        seedReviewProposalTranscript(conversation, proposal: proposal, endingAt: modifiedAt, into: context)
        thread.linkedPullRequests = [link(proposal.pullRequest, at: modifiedAt)]
        return thread
    }

    // MARK: Builders

    private static func makeThread(name: String, project: Project?, modifiedAt: Date) -> AgentThread {
        AgentThread(
            name: name,
            hasCustomName: true,
            // Completed setup is what keeps the project-trust gate from firing, which would
            // otherwise offer to write a fake path into the user's real `~/.claude.json`.
            hasCompletedInitialSetup: true,
            modifiedAt: modifiedAt,
            project: project
        )
    }

    /// A Task thread's mode has to be set at init alongside its descriptor: the descriptor's
    /// getter returns nil unless `mode == .task`.
    private static func makeTaskThread(
        name: String,
        workspace: String,
        modifiedAt: Date,
        into context: ModelContext
    ) -> AgentThread {
        let thread = AgentThread(
            name: name,
            hasCustomName: true,
            hasCompletedInitialSetup: true,
            modifiedAt: modifiedAt,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: workspace,
                ownershipStrategy: .privateOwned
            )
        )
        context.insert(thread)
        return thread
    }

    // A main conversation defaults its title to the thread's name, which is what a thread rename
    // cascades into in normal use — without it the tab strip labels the main tab "New thread".
    private static func makeConversation(
        id: String,
        thread: AgentThread,
        title: String? = nil,
        provider: String = "claude",
        isMain: Bool = true,
        displayOrder: Int = 0,
        isUnread: Bool = false,
        into context: ModelContext
    ) -> Conversation {
        let conversation = Conversation(
            id: id,
            title: title ?? (isMain ? thread.name : nil),
            provider: provider,
            isMain: isMain,
            displayOrder: displayOrder,
            isUnread: isUnread,
            thread: thread
        )
        context.insert(conversation)
        return conversation
    }

    static func link(_ id: PullRequestIdentifier, at date: Date) -> LinkedPullRequest {
        guard let summary = DemoPullRequestFixtures.summary(for: id) else {
            preconditionFailure("Demo fixtures must contain every linked pull request")
        }
        return LinkedPullRequest(summary: summary, linkedAt: date)
    }
}
#endif
