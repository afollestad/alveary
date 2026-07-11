import SwiftData
import XCTest

@testable import Alveary

extension SidebarViewModelTests {
    func testDraftCreationSaveFailureLeavesNothingReusableAndPreservesPendingChanges() async throws {
        var shouldFailCreation = true
        let fixture = try SidebarTestFixture(saveThreadCreation: { context in
            if shouldFailCreation {
                shouldFailCreation = false
                throw DraftThreadCreationSaveError.forced
            }
            try context.save()
        })
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/draft-create-failure")
        let unrelatedProject = try fixture.insertProject(name: "Pending", path: "/tmp/draft-create-pending")
        unrelatedProject.name = "Persisted pending project"

        do {
            _ = try await fixture.viewModel.openDraftThread(project: project)
            XCTFail("Expected draft creation save to fail")
        } catch DraftThreadCreationSaveError.forced {
            // expected
        }

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
        let verificationContext = ModelContext(fixture.container)
        let unrelatedPath = unrelatedProject.path
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == unrelatedPath
        })
        XCTAssertEqual(try verificationContext.fetch(descriptor).first?.name, "Persisted pending project")

        let retryDraft = try await fixture.viewModel.openDraftThread(project: project)
        XCTAssertTrue(retryDraft.isDraft)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 1)
    }
}

private enum DraftThreadCreationSaveError: Error {
    case forced
}
