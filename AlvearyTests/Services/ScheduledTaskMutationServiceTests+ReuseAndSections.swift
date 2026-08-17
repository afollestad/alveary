import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskMutationServiceTests {
    func testEditPreservesReuseLinkAcrossAgentSettingChanges() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertReuseDefinition()
        let reused = AgentThread(name: "Rolling thread", mode: .task)
        definition.reusedThread = reused
        try fixture.context.save()

        try fixture.service.edit(
            definitionID: definition.id,
            expectedRevision: 1,
            edit: fixture.makeReuseEdit(model: "gpt-6", effort: "low", permissionMode: "acceptEdits")
        )

        XCTAssertEqual(definition.reusedThread?.persistentModelID, reused.persistentModelID)
        XCTAssertEqual(definition.model, "gpt-6")
    }

    func testEditDropsReuseLinkWhenWorkspaceProviderOrDestinationChanges() throws {
        let fixture = try ScheduledTaskMutationFixture()
        for edit in [
            fixture.makeReuseEdit(providerID: "claude"),
            fixture.makeReuseEdit(grantedRoots: ["/tmp"]),
            fixture.makeReuseEdit(destination: .newThreadPerRun)
        ] {
            let definition = try fixture.insertReuseDefinition()
            definition.reusedThread = AgentThread(name: "Rolling thread", mode: .task)
            try fixture.context.save()

            try fixture.service.edit(definitionID: definition.id, expectedRevision: 1, edit: edit)

            XCTAssertNil(definition.reusedThread)
        }
    }

    func testCreateStoresThreadSectionOnlyForProjectlessNewThreadDestinations() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()

        let sectioned = try fixture.service.create(edit: fixture.makeReuseEdit(threadSection: section))
        XCTAssertEqual(sectioned.threadSection?.id, "reports")

        let project = Project(path: "/tmp/alveary", name: "Alveary")
        fixture.context.insert(project)
        try fixture.context.save()
        let projectBacked = try fixture.service.create(
            edit: fixture.makeReuseEdit(
                workspaceKind: .project,
                project: project,
                threadSection: section
            )
        )
        XCTAssertNil(projectBacked.threadSection)
    }

    func testCreateRejectsABuiltinSection() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let builtin = SidebarSection(id: "tasks-row", kind: .tasks, name: "Tasks", sortOrder: 0)
        fixture.context.insert(builtin)
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.service.create(edit: fixture.makeReuseEdit(threadSection: builtin))
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .sectionUnavailable)
        }
    }

    func testResumeDoesNotRequireAReuseLink() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertReuseDefinition(state: .paused)
        XCTAssertNil(definition.reusedThread)

        try fixture.service.resume(
            definitionID: definition.id,
            expectedRevision: 1,
            at: Date(timeIntervalSince1970: 600)
        )

        // A missing link just means the next run mints a fresh thread.
        XCTAssertEqual(definition.state, .active)
    }
}

extension ScheduledTaskMutationFixture {
    func insertReuseDefinition(state: ScheduledTaskState = .active) throws -> ScheduledTask {
        let definition = ScheduledTask(
            title: "Rolling schedule",
            prompt: "Continue the work.",
            destination: .reusedThread,
            state: state,
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: "Etc/UTC",
            providerID: "codex"
        )
        context.insert(definition)
        try context.save()
        return definition
    }

    func makeReuseEdit(
        destination: ScheduledTaskDestination = .reusedThread,
        providerID: String = "codex",
        model: String? = nil,
        effort: String = AppSettings.defaultEffortLevel,
        permissionMode: String = "default",
        workspaceKind: ScheduledTaskWorkspaceKind = .privateWorkspace,
        grantedRoots: [String] = [],
        project: Project? = nil,
        threadSection: SidebarSection? = nil
    ) -> ScheduledTaskDefinitionEdit {
        ScheduledTaskDefinitionEdit(
            title: "Rolling schedule",
            prompt: "Continue the work.",
            destination: destination,
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: "Etc/UTC",
            providerID: providerID,
            model: model,
            effort: effort,
            permissionMode: permissionMode,
            workspaceKind: workspaceKind,
            workspaceStrategy: .worktree,
            grantedRoots: grantedRoots,
            project: project,
            threadSection: threadSection
        )
    }
}
