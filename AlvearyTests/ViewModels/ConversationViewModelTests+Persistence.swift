import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testFlushPendingSaveWaitsForFollowUpSave() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let generation = UUID()
        fixture.viewModel.state.activeBufferGeneration = generation
        fixture.viewModel.state.lastObservedEventIndex = 1

        fixture.viewModel.scheduleSave()
        fixture.viewModel.state.lastObservedEventIndex = 2
        fixture.viewModel.scheduleSave()

        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 2)
    }
}
