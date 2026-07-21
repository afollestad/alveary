import XCTest

@testable import Alveary

@MainActor
extension SkillsViewModelTests {
    func testPaneFocusRestorationIDUsesInvokingControlAndSurvivesDismissal() throws {
        let skill = makeSkill(id: "focus-details")
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [skill], catalog: []))

        viewModel.requestNewSkill(focusRestorationID: "skills-new-empty")
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-new-empty")
        viewModel.dismissActivePane()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-new-empty")

        viewModel.requestDetails(for: skill)
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-details-focus-details")
        viewModel.dismissActivePane()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-details-focus-details")

        viewModel.requestNewSkill()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-new")
        viewModel.dismissActivePane()
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-new")
    }

    func testDismissingCapturedTargetDoesNotCloseNewActiveTarget() throws {
        let skill = makeSkill(id: "active-details")
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [skill], catalog: []))
        viewModel.requestNewSkill()
        let capturedGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)
        viewModel.requestDetails(for: skill)

        viewModel.dismissPane(.newSkill, generation: capturedGeneration)

        XCTAssertNil(viewModel.newSkillSession)
        XCTAssertEqual(viewModel.activePaneTarget, .details(skill.id))
        XCTAssertNotNil(viewModel.detailSessions[skill.id])
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testStaleDismissalCannotCloseReopenedSameTarget() throws {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        viewModel.requestNewSkill()
        let staleGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)
        viewModel.dismissActivePane()
        viewModel.requestNewSkill()
        let reopenedGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)

        viewModel.dismissPane(.newSkill, generation: staleGeneration)

        XCTAssertNotEqual(reopenedGeneration, staleGeneration)
        XCTAssertEqual(viewModel.newSkillSession?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.activePaneTarget, .newSkill)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }

    func testRequestingDeactivatedSameTargetCreatesFreshDefaultGenerationBeforeCompletion() throws {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        viewModel.requestNewSkill()
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "stale-draft",
            description: "Stale description",
            instructions: "Stale instructions"
        ))
        let staleGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)

        viewModel.deactivatePane(.newSkill, generation: staleGeneration)
        viewModel.requestNewSkill()
        let reopenedGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)

        XCTAssertNotEqual(reopenedGeneration, staleGeneration)
        XCTAssertEqual(viewModel.newSkillSession?.draft, NewSkillDraft())
        XCTAssertEqual(viewModel.activePaneTarget, .newSkill)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)

        viewModel.dismissPane(.newSkill, generation: staleGeneration)

        XCTAssertEqual(viewModel.newSkillSession?.generation, reopenedGeneration)
        XCTAssertEqual(viewModel.activePaneTarget, .newSkill)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testDismissalWithoutFocusRestorationDoesNotBumpGenerationWhenNoTargetIsActive() throws {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        viewModel.requestNewSkill()
        let generation = try XCTUnwrap(viewModel.newSkillSession?.generation)

        viewModel.deactivatePane(.newSkill, generation: generation)
        viewModel.dismissPane(.newSkill, generation: generation, restoreFocus: false)

        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertNil(viewModel.newSkillSession)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testDismissalWithoutFocusRestorationClearsMatchingActiveTarget() throws {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        viewModel.requestNewSkill()
        let generation = try XCTUnwrap(viewModel.newSkillSession?.generation)

        viewModel.dismissPane(.newSkill, generation: generation, restoreFocus: false)

        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertNil(viewModel.newSkillSession)
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testRequestingPendingSuccessfulCreateStartsFreshDraftWithoutFocusBump() async throws {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        viewModel.requestNewSkill(focusRestorationID: "skills-new-empty")
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "created-skill",
            description: "Created description",
            instructions: "Created instructions"
        ))
        let completedGeneration = try XCTUnwrap(viewModel.newSkillSession?.generation)

        await viewModel.submitNewSkill()
        let request = PaneSessionDismissalRequest(target: SkillsPaneTarget.newSkill, generation: completedGeneration)
        XCTAssertTrue(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-new")

        viewModel.requestNewSkill()

        XCTAssertNotEqual(viewModel.newSkillSession?.generation, completedGeneration)
        XCTAssertEqual(viewModel.newSkillSession?.draft, NewSkillDraft())
        XCTAssertEqual(viewModel.activePaneTarget, .newSkill)
        XCTAssertFalse(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testSuccessfulCreateRetainsSessionUntilAnimatedDismissalCompletes() async throws {
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [], catalog: []))
        viewModel.requestNewSkill()
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "new-skill",
            description: "A new skill",
            instructions: "Do useful work."
        ))
        let generation = try XCTUnwrap(viewModel.newSkillSession?.generation)

        await viewModel.submitNewSkill()

        let request = PaneSessionDismissalRequest(target: SkillsPaneTarget.newSkill, generation: generation)
        XCTAssertTrue(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.activePaneTarget, .newSkill)
        XCTAssertEqual(viewModel.newSkillSession?.generation, generation)
        XCTAssertEqual(viewModel.newSkillSession?.isSubmitting, true)

        viewModel.deactivatePane(.newSkill, generation: generation)
        XCTAssertNil(viewModel.activePaneTarget)
        XCTAssertEqual(viewModel.newSkillSession?.generation, generation)

        viewModel.dismissPane(.newSkill, generation: generation)
        XCTAssertNil(viewModel.newSkillSession)
        XCTAssertFalse(viewModel.pendingPaneDismissals.contains(request))
        XCTAssertEqual(viewModel.paneDismissalGeneration, 1)
    }

    func testCompletingDismissalDoesNotRestoreFocusOverNewActiveTarget() throws {
        let skill = makeSkill(id: "new-active-details")
        let viewModel = SkillsViewModel(skillsService: SkillsMockService(installed: [skill], catalog: []))
        viewModel.requestNewSkill()
        let generation = try XCTUnwrap(viewModel.newSkillSession?.generation)
        viewModel.deactivatePane(.newSkill, generation: generation)
        viewModel.requestDetails(for: skill)

        viewModel.dismissPane(.newSkill, generation: generation)

        XCTAssertEqual(viewModel.activePaneTarget, .details(skill.id))
        XCTAssertNotNil(viewModel.detailSessions[skill.id])
        XCTAssertEqual(viewModel.paneDismissalGeneration, 0)
    }

    func testDelayedCreateDoesNotReplaceNewTargetFocusRestorationID() async throws {
        let skill = makeSkill(id: "new-active-details")
        let viewModel = SkillsViewModel(
            skillsService: SkillsMockService(
                installed: [skill],
                catalog: [],
                createDelay: .milliseconds(200)
            )
        )
        viewModel.requestNewSkill(focusRestorationID: "skills-new-empty")
        viewModel.updateNewSkillDraft(NewSkillDraft(
            name: "created-skill",
            description: "Created description",
            instructions: "Created instructions"
        ))

        let submission = Task { await viewModel.submitNewSkill() }
        try? await Task.sleep(for: .milliseconds(50))
        viewModel.requestDetails(for: skill)
        await submission.value

        XCTAssertEqual(viewModel.activePaneTarget, .details(skill.id))
        XCTAssertEqual(viewModel.paneFocusRestorationID, "skills-details-new-active-details")
    }
}
