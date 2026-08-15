import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SidebarSectionServiceTests: XCTestCase {
    // MARK: Seeding

    func testEnsureBuiltinSectionsSeedsOnceAtTheFixedLayout() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)

        XCTAssertTrue(try service.ensureBuiltinSections())

        let sections = try orderedSections(fixture)
        XCTAssertEqual(sections.map(\.kind), [.pinned, .projects, .tasks])
        XCTAssertEqual(sections.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(sections.map(\.name), ["Pinned", "Projects", "Tasks"])

        XCTAssertFalse(try service.ensureBuiltinSections())
        XCTAssertEqual(try orderedSections(fixture).count, 3)
    }

    func testEnsureBuiltinSectionsCollapsesDuplicateBuiltinRows() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        fixture.context.insert(SidebarSection(kind: .tasks, name: "Tasks", sortOrder: 0))
        fixture.context.insert(SidebarSection(kind: .tasks, name: "Tasks", sortOrder: 5))
        try fixture.context.save()

        XCTAssertTrue(try service.ensureBuiltinSections())

        let sections = try orderedSections(fixture)
        XCTAssertEqual(sections.map(\.kind).filter { $0 == .tasks }.count, 1)
        XCTAssertEqual(Set(sections.map(\.kind)), [.pinned, .projects, .tasks])
        XCTAssertEqual(sections.map(\.sortOrder), [0, 1, 2])
    }

    // MARK: Creation and naming

    func testCreateSectionAppendsAtTheBottom() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)

        let alphaID = try createdCustomID(service.createSection(name: "Alpha"))
        let betaID = try createdCustomID(service.createSection(name: "Beta"))

        let sections = try orderedSections(fixture)
        XCTAssertEqual(sections.map(\.sortOrder), [0, 1, 2, 3, 4])
        XCTAssertEqual(sections.suffix(2).map(\.id), [alphaID, betaID])
        XCTAssertEqual(sections.suffix(2).map(\.name), ["Alpha", "Beta"])
    }

    func testCreateSectionTrimsAndValidatesNames() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)

        _ = try createdCustomID(service.createSection(name: "  Gamma  "))
        XCTAssertNotNil(try service.section(named: "Gamma"))

        XCTAssertThrowsError(try service.createSection(name: "   ")) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .invalidName)
        }
        let overlongName = String(repeating: "x", count: SidebarSectionService.maximumNameLength + 1)
        XCTAssertThrowsError(try service.createSection(name: overlongName)) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .nameTooLong)
        }
    }

    func testCreateSectionIsCaseInsensitivelyIdempotent() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)

        _ = try createdCustomID(service.createSection(name: "Research"))
        guard case .alreadyExists(let existing) = try service.createSection(name: "research") else {
            return XCTFail("Expected alreadyExists for a case-variant duplicate")
        }
        XCTAssertEqual(existing.name, "Research")
        XCTAssertEqual(try orderedSections(fixture).count, 4)
    }

    func testCreateSectionTreatsBuiltinNamesAsAlreadyExisting() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)

        guard case .alreadyExists(let existing) = try service.createSection(name: "tasks") else {
            return XCTFail("Expected alreadyExists for a builtin name")
        }
        XCTAssertEqual(existing.id, .tasks)
        XCTAssertEqual(try orderedSections(fixture).count, 3)
    }

    // MARK: Rename

    func testRenameSectionValidatesAgainstLiveNames() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let alphaID = try createdCustomID(service.createSection(name: "Alpha"))
        _ = try createdCustomID(service.createSection(name: "Beta"))

        XCTAssertEqual(try service.renameSection(id: alphaID, to: "Bravo").name, "Bravo")
        // A case-only rename of itself is allowed; another live name is not, builtins included.
        XCTAssertEqual(try service.renameSection(id: alphaID, to: "bravo").name, "bravo")
        XCTAssertThrowsError(try service.renameSection(id: alphaID, to: "beta")) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .duplicateName(existing: "Beta"))
        }
        XCTAssertThrowsError(try service.renameSection(id: alphaID, to: "Tasks")) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .duplicateName(existing: "Tasks"))
        }
        XCTAssertThrowsError(try service.renameSection(id: "missing", to: "Anything")) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .sectionMissing)
        }
    }

    func testRenameSectionRefusesBuiltinRows() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        try service.ensureBuiltinSections()
        let tasksRow = try XCTUnwrap(try orderedSections(fixture).first { $0.kind == .tasks })

        XCTAssertThrowsError(try service.renameSection(id: tasksRow.id, to: "Chores")) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .builtinSectionImmutable)
        }
    }

    // MARK: Removal

    func testRemoveSectionClearsMembershipOnEveryMemberIncludingArchived() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let alphaID = try createdCustomID(service.createSection(name: "Alpha"))
        _ = try createdCustomID(service.createSection(name: "Beta"))
        let alphaRow = try XCTUnwrap(fixture.context.resolveSidebarSection(id: alphaID))
        let active = makeTask(name: "Active", in: fixture)
        let archived = makeTask(name: "Archived", archivedAt: Date(), in: fixture)
        let pinned = makeTask(name: "Pinned", isPinned: true, pinnedSortOrder: 0, in: fixture)
        active.customSection = alphaRow
        archived.customSection = alphaRow
        pinned.customSection = alphaRow
        try fixture.context.save()

        XCTAssertEqual(try service.removeSection(id: alphaID), 3)

        XCTAssertNil(fixture.context.resolveSidebarSection(id: alphaID))
        XCTAssertNil(active.customSection)
        XCTAssertNil(archived.customSection)
        XCTAssertNil(pinned.customSection)
        // The pin itself survives removal; only membership clears.
        XCTAssertTrue(pinned.isPinned)
        XCTAssertEqual(try orderedSections(fixture).map(\.sortOrder), [0, 1, 2, 3])
    }

    func testRemoveSectionRefusesBuiltinsAndMissingRows() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        try service.ensureBuiltinSections()
        let pinnedRow = try XCTUnwrap(try orderedSections(fixture).first { $0.kind == .pinned })

        XCTAssertThrowsError(try service.removeSection(id: pinnedRow.id)) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .builtinSectionImmutable)
        }
        XCTAssertThrowsError(try service.removeSection(id: "missing")) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .sectionMissing)
        }
    }

    // MARK: Reorder

    func testMoveSectionReordersAroundVisibleAnchors() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let alphaID = try createdCustomID(service.createSection(name: "Alpha"))

        XCTAssertTrue(try service.moveSection(id: .custom(alphaID), before: .pinned))
        XCTAssertEqual(
            try orderedSections(fixture).map(\.sectionID),
            [.custom(alphaID), .pinned, .projects, .tasks]
        )

        XCTAssertTrue(try service.moveSection(id: .pinned, before: nil))
        XCTAssertEqual(
            try orderedSections(fixture).map(\.sectionID),
            [.custom(alphaID), .projects, .tasks, .pinned]
        )
        XCTAssertEqual(try orderedSections(fixture).map(\.sortOrder), [0, 1, 2, 3])

        // Moving a section before its current successor changes nothing.
        XCTAssertFalse(try service.moveSection(id: .projects, before: .tasks))

        XCTAssertThrowsError(try service.moveSection(id: .custom("missing"), before: nil)) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .sectionMissing)
        }
    }

    // MARK: Thread moves

    func testMoveThreadIntoCustomSectionUnpinsDetachesAndSetsMembershipInOneSave() throws {
        let fixture = try SidebarTestFixture()
        var saveCount = 0
        let service = SidebarSectionService(
            modelContext: fixture.context,
            saveSectionChanges: { context in
                saveCount += 1
                try context.save()
            }
        )
        let sectionID = try createdCustomID(service.createSection(name: "Research"))
        let project = try fixture.insertProject(name: "Home", path: "/tmp/section-move")
        let task = AgentThread(name: "Nested", isPinned: true, pinnedSortOrder: 0, mode: .task, project: project)
        fixture.context.insert(task)
        try fixture.context.save()

        saveCount = 0
        XCTAssertEqual(try service.moveThread(threadID: task.persistentModelID, to: .custom(sectionID: sectionID)), .moved)

        XCTAssertEqual(saveCount, 1)
        XCTAssertNil(task.project)
        XCTAssertFalse(task.isPinned)
        XCTAssertNil(task.pinnedSortOrder)
        XCTAssertEqual(task.customSection?.id, sectionID)

        XCTAssertEqual(
            try service.moveThread(threadID: task.persistentModelID, to: .custom(sectionID: sectionID)),
            .alreadyThere
        )
    }

    func testMoveThreadToTasksClearsMembership() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let sectionID = try createdCustomID(service.createSection(name: "Research"))
        let task = makeTask(name: "Member", in: fixture)
        task.customSection = try XCTUnwrap(fixture.context.resolveSidebarSection(id: sectionID))
        try fixture.context.save()

        XCTAssertEqual(try service.moveThread(threadID: task.persistentModelID, to: .tasks), .moved)
        XCTAssertNil(task.customSection)

        XCTAssertEqual(try service.moveThread(threadID: task.persistentModelID, to: .tasks), .alreadyThere)
    }

    func testMoveThreadRefusesIneligibleThreads() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let sectionID = try createdCustomID(service.createSection(name: "Research"))
        let target = SidebarSectionService.MoveTarget.custom(sectionID: sectionID)

        let projectThread = AgentThread(name: "Project-mode", mode: .project)
        let archived = makeTask(name: "Archived", archivedAt: Date(), in: fixture)
        fixture.context.insert(projectThread)
        try fixture.context.save()

        XCTAssertThrowsError(try service.moveThread(threadID: projectThread.persistentModelID, to: target)) { error in
            XCTAssertEqual(error as? SidebarSectionServiceError, .threadNotEligible)
        }
        XCTAssertThrowsError(try service.moveThread(threadID: archived.persistentModelID, to: target)) { error in
            guard case .threadMissing? = error as? SidebarViewModelError else {
                return XCTFail("Expected threadMissing, got \(error)")
            }
        }
    }

    func testMoveThreadRefusesUnpinWhenScheduledAttachmentProtectsThePin() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let sectionID = try createdCustomID(service.createSection(name: "Research"))
        let task = makeTask(name: "Guarded", isPinned: true, pinnedSortOrder: 0, in: fixture)
        fixture.context.insert(ScheduledTask(
            title: "Nightly sweep",
            prompt: "Continue in the task.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            createdAt: Date(timeIntervalSince1970: 100),
            targetThread: task
        ))
        try fixture.context.save()

        XCTAssertThrowsError(
            try service.moveThread(threadID: task.persistentModelID, to: .custom(sectionID: sectionID))
        ) { error in
            guard case .scheduledTaskAttachment("Nightly sweep")? = error as? SidebarViewModelError else {
                return XCTFail("Expected the scheduled-attachment refusal, got \(error)")
            }
        }
        XCTAssertTrue(task.isPinned)
        XCTAssertNil(task.customSection)
    }

    func testMoveThreadFailingSaveRollsBackEverything() throws {
        let fixture = try SidebarTestFixture()
        let workingService = SidebarSectionService(modelContext: fixture.context)
        let sectionID = try createdCustomID(workingService.createSection(name: "Research"))
        let task = makeTask(name: "Pinned", isPinned: true, pinnedSortOrder: 0, in: fixture)
        try fixture.context.save()

        struct SaveFailure: Error {}
        let failingService = SidebarSectionService(
            modelContext: fixture.context,
            saveSectionChanges: { _ in throw SaveFailure() }
        )

        XCTAssertThrowsError(
            try failingService.moveThread(threadID: task.persistentModelID, to: .custom(sectionID: sectionID))
        ) { error in
            XCTAssertTrue(error is SaveFailure)
        }
        XCTAssertTrue(task.isPinned)
        XCTAssertEqual(task.pinnedSortOrder, 0)
        XCTAssertNil(task.customSection)
    }

    // MARK: Normalization repair

    func testOrderNormalizationClearsMembershipThatLeftTheTasksPopulation() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        let sectionID = try createdCustomID(service.createSection(name: "Research"))
        let section = try XCTUnwrap(fixture.context.resolveSidebarSection(id: sectionID))
        let project = try fixture.insertProject(name: "Home", path: "/tmp/normalize-membership")
        let placed = AgentThread(name: "Placed", mode: .task, project: project)
        let wrongMode = AgentThread(name: "Wrong mode", mode: .project)
        let archivedMember = makeTask(name: "Archived member", archivedAt: Date(), in: fixture)
        fixture.context.insert(placed)
        fixture.context.insert(wrongMode)
        placed.customSection = section
        wrongMode.customSection = section
        archivedMember.customSection = section
        try fixture.context.save()

        XCTAssertTrue(try SidebarOrderNormalization.normalize(in: fixture.context))
        try fixture.context.save()

        XCTAssertNil(placed.customSection)
        XCTAssertNil(wrongMode.customSection)
        // Archived projectless Tasks keep membership so a restore returns them to their section.
        XCTAssertEqual(archivedMember.customSection?.id, sectionID)
    }

    func testSectionNormalizationClearsMembershipPointingAtBuiltinRows() throws {
        let fixture = try SidebarTestFixture()
        let service = SidebarSectionService(modelContext: fixture.context)
        try service.ensureBuiltinSections()
        let tasksRow = try XCTUnwrap(try orderedSections(fixture).first { $0.kind == .tasks })
        let task = makeTask(name: "Misfiled", in: fixture)
        task.customSection = tasksRow
        try fixture.context.save()

        XCTAssertTrue(try SidebarSectionNormalization.normalize(in: fixture.context))
        try fixture.context.save()

        XCTAssertNil(task.customSection)
    }
}

private extension SidebarSectionServiceTests {
    func orderedSections(_ fixture: SidebarTestFixture) throws -> [SidebarSection] {
        SidebarSectionNormalization.orderedSections(
            try fixture.context.fetch(FetchDescriptor<SidebarSection>())
        )
    }

    func createdCustomID(_ outcome: SidebarSectionService.CreateOutcome) throws -> String {
        guard case .created(let descriptor) = outcome,
              case .custom(let id) = descriptor.id else {
            XCTFail("Expected a created custom section, got \(outcome)")
            throw SidebarSectionServiceError.sectionMissing
        }
        return id
    }

    @discardableResult
    func makeTask(
        name: String,
        isPinned: Bool = false,
        pinnedSortOrder: Int? = nil,
        archivedAt: Date? = nil,
        in fixture: SidebarTestFixture
    ) -> AgentThread {
        let task = AgentThread(
            name: name,
            isPinned: isPinned,
            pinnedSortOrder: pinnedSortOrder,
            archivedAt: archivedAt,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/\(UUID().uuidString)",
                ownershipStrategy: .projectLocal
            )
        )
        fixture.context.insert(task)
        return task
    }
}
