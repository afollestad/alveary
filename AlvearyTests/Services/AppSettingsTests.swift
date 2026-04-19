import Foundation
import XCTest

@testable import Alveary

final class AppSettingsTests: XCTestCase {
    func testDefaultWorktreesBaseDirectory() {
        XCTAssertEqual(AppSettings().worktreesBaseDirectory, "~/Documents/worktrees")
    }

    func testExpandedWorktreesBaseDirectoryExpandsTilde() {
        var settings = AppSettings()
        settings.worktreesBaseDirectory = "~/Development/worktrees"
        let expanded = settings.expandedWorktreesBaseDirectory
        let home = (NSHomeDirectory() as NSString) as String

        XCTAssertFalse(expanded.contains("~"))
        XCTAssertTrue(expanded.hasPrefix(home))
        XCTAssertTrue(expanded.hasSuffix("/Development/worktrees"))
    }

    func testExpandedWorktreesBaseDirectoryPassesThroughAbsolutePaths() {
        var settings = AppSettings()
        settings.worktreesBaseDirectory = "/tmp/alveary-worktrees"

        XCTAssertEqual(settings.expandedWorktreesBaseDirectory, "/tmp/alveary-worktrees")
    }

    func testExpandedWorktreesBaseDirectoryFallsBackToDefaultForRelativePaths() {
        var settings = AppSettings()
        settings.worktreesBaseDirectory = "relative/path"
        let defaultExpanded = (AppSettings().worktreesBaseDirectory as NSString).expandingTildeInPath

        XCTAssertEqual(settings.expandedWorktreesBaseDirectory, defaultExpanded)
    }

    func testNormalizedRestoresDefaultWhenWorktreesBaseIsEmpty() {
        var settings = AppSettings()
        settings.worktreesBaseDirectory = ""

        XCTAssertEqual(settings.normalized().worktreesBaseDirectory, "~/Documents/worktrees")
    }

    func testNormalizedRestoresDefaultWhenWorktreesBaseIsWhitespace() {
        var settings = AppSettings()
        settings.worktreesBaseDirectory = "   \n  "

        XCTAssertEqual(settings.normalized().worktreesBaseDirectory, "~/Documents/worktrees")
    }

    func testNormalizedTrimsWhitespaceAroundWorktreesBase() {
        var settings = AppSettings()
        settings.worktreesBaseDirectory = "  /tmp/worktrees  "

        XCTAssertEqual(settings.normalized().worktreesBaseDirectory, "/tmp/worktrees")
    }

    func testDecodeFillsInDefaultWorktreesBaseWhenFieldIsMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.worktreesBaseDirectory, "~/Documents/worktrees")
    }

    func testNormalizedClampsUnknownDefaultModelToSentinel() {
        var settings = AppSettings()
        settings.defaultModel = "gpt-9"

        XCTAssertEqual(settings.normalized().defaultModel, AppSettings.defaultModelValue)
    }

    func testNormalizedPreservesSupportedDefaultModel() {
        var settings = AppSettings()
        settings.defaultModel = "opus"

        XCTAssertEqual(settings.normalized().defaultModel, "opus")
    }
}
