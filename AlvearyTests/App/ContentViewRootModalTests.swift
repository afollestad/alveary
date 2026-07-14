import XCTest

@testable import Alveary

@MainActor
final class ContentViewRootModalTests: XCTestCase {
    func testOnboardingModalSuppressesImagePreviewModal() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "DA49D9E9-6326-4199-BA27-3654DB1E2B20"))
        let request = AppImagePreviewRequest(
            id: requestID,
            title: "Preview",
            source: .fileURL(URL(fileURLWithPath: "/tmp/preview.png"))
        )

        let modalKind = ContentView.rootWindowModalKind(
            isOnboardingPresented: true,
            imagePreviewRequest: request
        )

        XCTAssertEqual(modalKind, .onboarding)
    }

    func testImagePreviewModalIsUsedWhenOnboardingIsHidden() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "C4B88CC9-98FB-42DC-9F19-51C94399F4B9"))
        let request = AppImagePreviewRequest(
            id: requestID,
            title: "Preview",
            source: .fileURL(URL(fileURLWithPath: "/tmp/preview.png"))
        )

        let modalKind = ContentView.rootWindowModalKind(
            isOnboardingPresented: false,
            imagePreviewRequest: request
        )

        XCTAssertEqual(modalKind, .imagePreview(requestID))
    }

    func testRootModalIsNilWhenOnboardingIsHiddenAndImagePreviewIsAbsent() {
        let modalKind = ContentView.rootWindowModalKind(
            isOnboardingPresented: false,
            imagePreviewRequest: nil
        )

        XCTAssertNil(modalKind)
    }

    func testProposalModalIsUsedWhenHigherPriorityModalsAreAbsent() {
        let modalKind = ContentView.rootWindowModalKind(
            isOnboardingPresented: false,
            imagePreviewRequest: nil,
            scheduledTaskProposalID: "proposal-1"
        )

        XCTAssertEqual(modalKind, .scheduledTaskProposal("proposal-1"))
    }

    func testImagePreviewSuppressesProposalModal() throws {
        let requestID = try XCTUnwrap(UUID(uuidString: "C06B7D95-6E34-4AB3-989B-F7BC727668A6"))
        let request = AppImagePreviewRequest(
            id: requestID,
            title: "Preview",
            source: .fileURL(URL(fileURLWithPath: "/tmp/preview.png"))
        )

        let modalKind = ContentView.rootWindowModalKind(
            isOnboardingPresented: false,
            imagePreviewRequest: request,
            scheduledTaskProposalID: "proposal-1"
        )

        XCTAssertEqual(modalKind, .imagePreview(requestID))
    }

    func testProposalModalIdentityChangesWhenConflictPresentationChanges() {
        let readyID = ContentView.scheduledTaskProposalModalID(
            proposalID: "proposal-1",
            conflictMessage: nil
        )
        let staleID = ContentView.scheduledTaskProposalModalID(
            proposalID: "proposal-1",
            conflictMessage: "This scheduled task changed after the proposal was opened."
        )
        let deletedID = ContentView.scheduledTaskProposalModalID(
            proposalID: "proposal-1",
            conflictMessage: "The scheduled task for this proposal was deleted."
        )

        XCTAssertNotEqual(readyID, staleID)
        XCTAssertNotEqual(staleID, deletedID)
    }
}
