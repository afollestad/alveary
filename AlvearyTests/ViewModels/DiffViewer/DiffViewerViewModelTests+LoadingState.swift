import XCTest

@testable import Alveary

@MainActor
extension DiffViewerViewModelTests {
    func testIsLoadingFilesIsTrueWhileRefreshingAfterDirectorySwitch() async {
        let fixture = DiffViewerTestFixture(
            gitService: DiffViewerMockGitService(
                statusResults: [.success([])],
                statusDelays: [.milliseconds(120)]
            )
        )
        defer { fixture.viewModel.tearDown() }

        XCTAssertFalse(fixture.viewModel.isLoadingFiles)

        // `status` fulfills the barrier *before* its 120ms sleep, so when
        // `fulfillment` resumes, the refresh is suspended mid-status and
        // `switchToDirectory`'s synchronous prefix has already flipped the flag.
        let statusEntered = expectation(description: "status call entered")
        await fixture.gitService.setOnStatus { statusEntered.fulfill() }

        let switchTask = Task {
            await fixture.viewModel.switchToDirectory(
                fixture.directory,
                baseRef: "main",
                remoteName: nil,
                conversationIds: []
            )
        }

        await fulfillment(of: [statusEntered], timeout: 2.0)
        XCTAssertTrue(fixture.viewModel.isLoadingFiles)

        await switchTask.value
        XCTAssertFalse(fixture.viewModel.isLoadingFiles)
    }
}
