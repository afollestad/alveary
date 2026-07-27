import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testTasksPlaceholderLabelNamesWhyTheBodyIsEmpty() {
        // Only emptiness matters to the label; the thread never touches a model context.
        let listedTask = AgentThread(name: "Listed", mode: .task)

        // Tasks exist but all are pinned or project-placed: the body says so rather than sitting
        // blank under the header. "No tasks" stays reserved for none existing anywhere.
        XCTAssertEqual(
            sidebarTasksPlaceholderLabel(activeTaskThreads: [], hasAnyActiveTaskThreads: true),
            "No tasks here"
        )
        XCTAssertEqual(
            sidebarTasksPlaceholderLabel(activeTaskThreads: [], hasAnyActiveTaskThreads: false),
            "No tasks"
        )
        XCTAssertNil(
            sidebarTasksPlaceholderLabel(activeTaskThreads: [listedTask], hasAnyActiveTaskThreads: true)
        )
    }
}
