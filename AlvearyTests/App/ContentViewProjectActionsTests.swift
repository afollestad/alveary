import Knit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ContentViewProjectActionsTests: XCTestCase {
    func testContentViewUsesModelContainerMainContextForViewModels() {
        let assembler = ScopedModuleAssembler<Resolver>([
            AppAssembly(),
            DataAssembly(isStoredInMemoryOnly: true)
        ])
        let resolver = assembler.resolver

        XCTAssertTrue(ContentView.makeViewModelContext(resolver: resolver) === resolver.modelContainer().mainContext)
    }

    func testProjectActionExecutionContextPrefersWorktreePathAndCarriesThreadMetadata() throws {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Toolbar Action", worktreePath: "/tmp/worktree", project: project)
        let action = AlvearyProjectConfig.ProjectAction(icon: "hammer", name: "Build", command: "./scripts/build.sh")

        let context = try XCTUnwrap(ProjectActionExecutionContext(thread: thread, action: action))

        XCTAssertEqual(context.title, "Build")
        XCTAssertEqual(context.projectName, "Alveary")
        XCTAssertEqual(context.threadID, thread.persistentModelID)
        XCTAssertEqual(context.threadName, "Toolbar Action")
        XCTAssertEqual(context.currentDirectory, "/tmp/worktree")
        XCTAssertEqual(context.command, "./scripts/build.sh")
    }

    func testProjectActionExecutionContextFallsBackToProjectPath() {
        let project = Project(path: "/tmp/project", name: "Alveary")
        let thread = AgentThread(name: "Toolbar Action", project: project)
        let action = AlvearyProjectConfig.ProjectAction(name: "Test", command: "./scripts/test.sh")

        let context = ProjectActionExecutionContext(thread: thread, action: action)

        XCTAssertEqual(context?.currentDirectory, "/tmp/project")
    }

    func testProjectActionExecutionContextReturnsNilWithoutRunnableDirectory() {
        let thread = AgentThread(name: "Toolbar Action")
        let action = AlvearyProjectConfig.ProjectAction(name: "Test", command: "./scripts/test.sh")

        XCTAssertNil(ProjectActionExecutionContext(thread: thread, action: action))
    }

    func testProjectActionOutputFormatterIncludesAllCapturedSections() {
        let result = ShellResult(
            stdout: "build ok",
            stderr: "warning",
            exitCode: 0,
            stdoutWasTruncated: true,
            stderrWasTruncated: false
        )

        XCTAssertEqual(
            ProjectActionOutputFormatter.format(result),
            "build ok\n\nstderr:\nwarning\n\nstdout was truncated."
        )
    }
}
