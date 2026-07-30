import Foundation
import XCTest

@testable import Alveary

@MainActor
extension PullRequestsViewModelTests {
    private static func upload(_ name: String, reference: String) -> GitHubAttachmentUpload {
        GitHubAttachmentUpload(fileURL: URL(fileURLWithPath: "/tmp/\(name)"), markdownReference: reference)
    }

    /// Opens a pane so `attachFiles` can resolve the repository to upload against.
    private func makeViewModelWithOpenPane(
        uploader: StubGitHubAttachmentUploadService,
        presentToast: @escaping @MainActor @Sendable (String) -> Void = { _ in }
    ) async -> (PullRequestsViewModel, PullRequestSummary) {
        let summary = makePullRequestSummary(number: 7, repo: "octo/alpha")
        let service = StubPullRequestsService()
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let viewModel = makePullRequestsViewModel(
            service: service,
            attachmentUploadService: uploader,
            presentToast: presentToast
        )
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        return (viewModel, summary)
    }

    func testAttachFilesShowsPlaceholdersImmediatelyThenSwapsInLinks() async {
        let uploader = StubGitHubAttachmentUploadService()
        let gate = PullRequestsServiceGate()
        uploader.gate = gate
        uploader.result = .success([
            Self.upload("a.png", reference: "![a.png](https://example.com/a)"),
            Self.upload("b.png", reference: "![b.png](https://example.com/b)")
        ])
        let (viewModel, _) = await makeViewModelWithOpenPane(uploader: uploader)
        let draft = PullRequestCommentDraftBox(markdown: "Looks good")

        viewModel.attachFiles(
            [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")],
            to: .composer,
            draft: draft
        )

        // Placeholders land synchronously, before the upload finishes.
        XCTAssertTrue(draft.markdown.contains("Uploading a.png…"), draft.markdown)
        XCTAssertTrue(draft.markdown.contains("Uploading b.png…"), draft.markdown)

        gate.open()
        for _ in 0..<2_000 where viewModel.isUploadingAttachments(to: .composer) {
            await Task.yield()
        }

        XCTAssertFalse(draft.markdown.contains("Uploading"), draft.markdown)
        XCTAssertTrue(draft.markdown.hasPrefix("Looks good"), draft.markdown)
        XCTAssertTrue(draft.markdown.contains("![a.png](https://example.com/a)"), draft.markdown)
        XCTAssertTrue(draft.markdown.contains("![b.png](https://example.com/b)"), draft.markdown)
    }

    func testAttachFilesAppendsReferencesToTheDraft() async {
        let uploader = StubGitHubAttachmentUploadService()
        uploader.result = .success([
            Self.upload("a.png", reference: "![a.png](https://example.com/a)"),
            Self.upload("b.png", reference: "![b.png](https://example.com/b)")
        ])
        let (viewModel, _) = await makeViewModelWithOpenPane(uploader: uploader)
        let draft = PullRequestCommentDraftBox(markdown: "Looks good")

        viewModel.attachFiles(
            [URL(fileURLWithPath: "/tmp/a.png"), URL(fileURLWithPath: "/tmp/b.png")],
            to: .composer,
            draft: draft
        )
        for _ in 0..<2_000 where viewModel.isUploadingAttachments(to: .composer) {
            await Task.yield()
        }

        // Asserted by content, not exact string: BlockInputKit normalizes block
        // separation on the document round trip, which is not what this covers.
        XCTAssertTrue(draft.markdown.hasPrefix("Looks good"), draft.markdown)
        XCTAssertTrue(draft.markdown.contains("![a.png](https://example.com/a)"), draft.markdown)
        XCTAssertTrue(draft.markdown.contains("![b.png](https://example.com/b)"), draft.markdown)
        XCTAssertEqual(uploader.uploadCalls.count, 1)
        XCTAssertEqual(uploader.uploadCalls.first?.repository, "octo/alpha")
    }

    func testInFlightUploadBlocksTheDestinationUntilItFinishes() async {
        let uploader = StubGitHubAttachmentUploadService()
        let gate = PullRequestsServiceGate()
        uploader.gate = gate
        uploader.result = .success([Self.upload("a.png", reference: "![a.png](https://example.com/a)")])
        let (viewModel, _) = await makeViewModelWithOpenPane(uploader: uploader)
        let draft = PullRequestCommentDraftBox(markdown: "")

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)

        // The flag flips synchronously; the upload itself runs in a task, so wait
        // for the call to register before counting invocations.
        XCTAssertTrue(viewModel.isUploadingAttachments(to: .composer))
        // The review footer's own destination stays free.
        XCTAssertFalse(viewModel.isUploadingAttachments(to: .reviewSummary))
        for _ in 0..<2_000 where uploader.uploadCalls.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(uploader.uploadCalls.count, 1)

        // A second attach on the busy destination is ignored rather than queued.
        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/b.png")], to: .composer, draft: draft)
        await Task.yield()
        XCTAssertEqual(uploader.uploadCalls.count, 1)

        gate.open()
        for _ in 0..<2_000 where viewModel.isUploadingAttachments(to: .composer) {
            await Task.yield()
        }
        XCTAssertFalse(viewModel.isUploadingAttachments(to: .composer))
    }

    func testFailedUploadKeepsTheDraftAndToastsTheError() async {
        let uploader = StubGitHubAttachmentUploadService()
        uploader.result = .failure(.uploadFailed("Network is down"))
        let toasts = ToastRecorder()
        let (viewModel, _) = await makeViewModelWithOpenPane(
            uploader: uploader,
            presentToast: { message in toasts.record(message) }
        )
        let draft = PullRequestCommentDraftBox(markdown: "Typed comment")

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)
        for _ in 0..<2_000 where toasts.messages.isEmpty {
            await Task.yield()
        }

        // The typed comment survives and the placeholder is withdrawn, so nothing
        // the user wrote is lost and no "Uploading…" text can be posted.
        XCTAssertEqual(draft.markdown, "Typed comment")
        XCTAssertFalse(draft.markdown.contains("Uploading"), draft.markdown)
        XCTAssertEqual(toasts.messages.count, 1)
        XCTAssertEqual(toasts.messages.first, "Uploading a.png failed. Network is down")
        XCTAssertFalse(viewModel.isUploadingAttachments(to: .composer))
    }

    func testAttachWithoutAnUploaderToastsInstallGuidance() async {
        let summary = makePullRequestSummary(number: 7)
        let service = StubPullRequestsService()
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let toasts = ToastRecorder()
        let viewModel = makePullRequestsViewModel(
            service: service,
            presentToast: { message in toasts.record(message) }
        )
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: PullRequestCommentDraftBox(markdown: ""))

        XCTAssertFalse(viewModel.supportsAttachmentUploads)
        XCTAssertEqual(toasts.messages.count, 1)
        XCTAssertEqual(
            toasts.messages.first,
            GitHubAttachmentUploadError.extensionMissing.localizedDescription
        )
    }

    /// A browser-session failure is a privacy grant to walk through, not a
    /// message: it must open the access-guidance sheet instead of toasting.
    func testSessionUnavailableFailureOpensAccessGuidanceInsteadOfToasting() async {
        let uploader = StubGitHubAttachmentUploadService()
        uploader.result = .failure(.sessionUnavailable("no session token found"))
        let toasts = ToastRecorder()
        let (viewModel, _) = await makeViewModelWithOpenPane(
            uploader: uploader,
            presentToast: { message in toasts.record(message) }
        )
        let draft = PullRequestCommentDraftBox(markdown: "Typed comment")

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)
        for _ in 0..<2_000 where viewModel.attachmentAccessRequest == nil {
            await Task.yield()
        }

        XCTAssertTrue(toasts.messages.isEmpty, toasts.messages.joined())
        XCTAssertEqual(draft.markdown, "Typed comment")
        XCTAssertEqual(viewModel.attachmentAccessRequest?.repository, "octo/alpha")
        XCTAssertEqual(viewModel.attachmentAccessRequest?.files, [URL(fileURLWithPath: "/tmp/a.png")])
        XCTAssertEqual(viewModel.attachmentAccessRequest?.destination, .composer)
        XCTAssertFalse(viewModel.isUploadingAttachments(to: .composer))
    }

    /// Retry must work after the pane is gone: the guidance sheet outlives it
    /// (the user detours through System Settings), so the request carries the
    /// repository the pane originally resolved.
    func testRetryFromAccessGuidanceReusesCapturedRepositoryAfterPaneCloses() async {
        let uploader = StubGitHubAttachmentUploadService()
        uploader.result = .failure(.sessionUnavailable("no session token found"))
        let (viewModel, summary) = await makeViewModelWithOpenPane(uploader: uploader)
        let draft = PullRequestCommentDraftBox(markdown: "")

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)
        for _ in 0..<2_000 where viewModel.attachmentAccessRequest == nil {
            await Task.yield()
        }

        let target = PullRequestPaneTarget.details(summary.id)
        guard let generation = viewModel.paneSessions[target]?.generation else {
            return XCTFail("Missing pane session")
        }
        viewModel.deactivatePane(target, generation: generation)
        viewModel.dismissPane(target, generation: generation, restoreFocus: false)

        uploader.result = .success([Self.upload("a.png", reference: "![a.png](https://example.com/a)")])
        viewModel.retryAttachmentUpload()
        XCTAssertNil(viewModel.attachmentAccessRequest)
        for _ in 0..<2_000 where viewModel.isUploadingAttachments(to: .composer) {
            await Task.yield()
        }

        XCTAssertEqual(uploader.uploadCalls.count, 2)
        XCTAssertEqual(uploader.uploadCalls.last?.repository, "octo/alpha")
        XCTAssertEqual(draft.markdown, "![a.png](https://example.com/a)")
    }

    func testDismissingAccessGuidanceClearsTheRequestWithoutUploading() async {
        let uploader = StubGitHubAttachmentUploadService()
        uploader.result = .failure(.sessionUnavailable("no session token found"))
        let (viewModel, _) = await makeViewModelWithOpenPane(uploader: uploader)
        let draft = PullRequestCommentDraftBox(markdown: "")

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)
        for _ in 0..<2_000 where viewModel.attachmentAccessRequest == nil {
            await Task.yield()
        }

        viewModel.dismissAttachmentAccessRequest()
        XCTAssertNil(viewModel.attachmentAccessRequest)
        // No retry happened: the failed attempt remains the only upload call.
        XCTAssertEqual(uploader.uploadCalls.count, 1)
        // A retry after dismissal is a no-op rather than a stale re-upload.
        viewModel.retryAttachmentUpload()
        await Task.yield()
        XCTAssertEqual(uploader.uploadCalls.count, 1)
    }

    /// Uploaded bytes seed the image caches before the references land in the
    /// draft — GitHub keeps fresh assets session-gated, so rendering must come
    /// from the local file, not a refetch.
    func testSuccessfulUploadSeedsImagesBeforeReplacingPlaceholders() async {
        let uploader = StubGitHubAttachmentUploadService()
        let upload = Self.upload("a.png", reference: "![a.png](https://example.com/a)")
        uploader.result = .success([upload])
        let summary = makePullRequestSummary(number: 7, repo: "octo/alpha")
        let service = StubPullRequestsService()
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let seeded = ToastRecorder()
        let viewModel = makePullRequestsViewModel(
            service: service,
            attachmentUploadService: uploader,
            attachmentImageSeeder: { seededUpload in
                // The placeholder must still be in the draft while seeding runs.
                seeded.record(seededUpload.markdownReference)
            }
        )
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        let draft = PullRequestCommentDraftBox(markdown: "")

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)
        for _ in 0..<2_000 where viewModel.isUploadingAttachments(to: .composer) {
            await Task.yield()
        }

        XCTAssertEqual(seeded.messages, ["![a.png](https://example.com/a)"])
        XCTAssertEqual(draft.markdown, "![a.png](https://example.com/a)")
    }

    func testRequestDetailsRegistersTheRepositoryForAttachmentImageResolution() async {
        let summary = makePullRequestSummary(number: 7, repo: "octo/alpha")
        let service = StubPullRequestsService()
        service.detailResult = .success(makePullRequestDetail(id: summary.id))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        let registered = ToastRecorder()
        let viewModel = makePullRequestsViewModel(
            service: service,
            attachmentImageRepositoryRegistrar: { repository in
                registered.record(repository)
            }
        )

        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))

        XCTAssertEqual(registered.messages, ["octo/alpha"])
    }

    /// A closed pane must not cancel an upload; the reference still lands in the
    /// draft the user was typing in.
    func testUploadSurvivesPaneDismissal() async {
        let uploader = StubGitHubAttachmentUploadService()
        let gate = PullRequestsServiceGate()
        uploader.gate = gate
        uploader.result = .success([Self.upload("a.png", reference: "![a.png](https://example.com/a)")])
        let (viewModel, summary) = await makeViewModelWithOpenPane(uploader: uploader)
        let draft = PullRequestCommentDraftBox(markdown: "")
        let target = PullRequestPaneTarget.details(summary.id)
        guard let generation = viewModel.paneSessions[target]?.generation else {
            return XCTFail("Missing pane session")
        }

        viewModel.attachFiles([URL(fileURLWithPath: "/tmp/a.png")], to: .composer, draft: draft)
        viewModel.deactivatePane(target, generation: generation)
        viewModel.dismissPane(target, generation: generation, restoreFocus: false)
        XCTAssertNil(viewModel.paneSessions[target])

        gate.open()
        for _ in 0..<2_000 where viewModel.isUploadingAttachments(to: .composer) {
            await Task.yield()
        }

        XCTAssertEqual(draft.markdown, "![a.png](https://example.com/a)")
    }
}

/// Main-actor recorder: the toast closure is `@Sendable` and cannot capture a
/// mutable local.
@MainActor
final class ToastRecorder {
    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }
}
