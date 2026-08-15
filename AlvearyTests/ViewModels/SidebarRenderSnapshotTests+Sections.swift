import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarRenderSnapshotTests {
    func testSectionDescriptorsFallBackToTheBuiltinLayoutBeforeRowsExist() throws {
        let fixture = try SidebarTestFixture()

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(snapshot.sectionDescriptors, SidebarSectionDescriptor.builtinFallback)
        XCTAssertEqual(snapshot.sectionDescriptors.map(\.id), [.pinned, .projects, .tasks])
    }

    func testSectionDescriptorsFollowThePersistedOrder() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        guard case .created(let research) = try service.createSection(name: "Research") else {
            return XCTFail("Expected a created section")
        }
        try service.moveSection(id: research.id, before: .pinned)

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(snapshot.sectionDescriptors.map(\.id), [research.id, .pinned, .projects, .tasks])
        XCTAssertEqual(snapshot.sectionDescriptors.first?.name, "Research")
    }

    func testCustomSectionMembershipSplitsTheTasksBucket() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        guard case .created(let research) = try service.createSection(name: "Research"),
              case .custom(let researchID) = research.id else {
            return XCTFail("Expected a created custom section")
        }
        let member = makeSectionTask(name: "Member", in: fixture)
        let plain = makeSectionTask(name: "Plain", in: fixture)
        member.customSection = fixture.context.resolveSidebarSection(id: researchID)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(snapshot.threads(inCustomSection: researchID).map(\.persistentModelID), [member.persistentModelID])
        XCTAssertEqual(snapshot.activeTaskThreads.map(\.persistentModelID), [plain.persistentModelID])
        XCTAssertEqual(snapshot.customSectionIDByTaskID, [member.persistentModelID: researchID])
        // Member rows join the visible-row count that gates the thread-order animation — and
        // leave it again when their section collapses, like every other collapsible section.
        XCTAssertEqual(snapshot.expandedThreadCount(expandedProjects: []), 2)
        XCTAssertEqual(
            snapshot.expandedThreadCount(expandedProjects: [], collapsedSections: [.custom(researchID)]),
            1
        )
    }

    func testPinnedMemberRendersUnderPinnedWhileKeepingItsMembership() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        guard case .created(let research) = try service.createSection(name: "Research"),
              case .custom(let researchID) = research.id else {
            return XCTFail("Expected a created custom section")
        }
        let pinnedMember = makeSectionTask(name: "Pinned member", isPinned: true, in: fixture)
        pinnedMember.pinnedSortOrder = 0
        pinnedMember.customSection = fixture.context.resolveSidebarSection(id: researchID)
        try fixture.context.save()

        let snapshot = try fixture.renderSnapshot()

        XCTAssertEqual(snapshot.pinnedItems.map(\.dragItem), [.pinnedTask(pinnedMember.persistentModelID)])
        XCTAssertTrue(snapshot.threads(inCustomSection: researchID).isEmpty)
        // Membership survives the pin so an unpin returns the row to its section.
        XCTAssertEqual(snapshot.customSectionIDByTaskID, [pinnedMember.persistentModelID: researchID])
    }
}

@MainActor
private func makeSectionTask(name: String, isPinned: Bool = false, in fixture: SidebarTestFixture) -> AgentThread {
    let task = AgentThread(
        name: name,
        isPinned: isPinned,
        mode: .task,
        taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/\(UUID().uuidString)",
            ownershipStrategy: .projectLocal
        )
    )
    fixture.context.insert(task)
    return task
}
