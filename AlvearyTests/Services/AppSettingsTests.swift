import Foundation
import XCTest

@testable import Alveary

final class AppSettingsTests: XCTestCase {
    func testDefaultWorktreesBaseDirectory() {
        XCTAssertEqual(AppSettings().worktreesBaseDirectory, "~/Documents/worktrees")
    }

    func testDefaultTerminalActionExpansionIsDisabled() {
        XCTAssertFalse(AppSettings().expandTerminalWhenActionsRun)
    }

    func testDefaultMaxTerminalSessionsIsTen() {
        XCTAssertEqual(AppSettings().maxTerminalSessions, 10)
    }

    func testDefaultEnterBehaviorIsQueue() {
        XCTAssertEqual(AppSettings().defaultEnterBehavior, .queue)
    }

    func testDefaultContextManagementSettings() {
        let settings = AppSettings()

        XCTAssertTrue(settings.contextManagementEnabled)
        XCTAssertEqual(settings.sessionHandoffWindowPercentage, AppSettings.defaultSessionHandoffWindowPercentage)
        XCTAssertTrue(settings.handoffContextCustomizationEnabled)
        XCTAssertTrue(settings.sessionHandoffPrompt.hasPrefix("Turn the current session into a prompt"))
        XCTAssertFalse(settings.sessionHandoffPrompt.contains("name: session-handoff"))
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

    func testDecodeDefaultsTerminalActionExpansionWhenFieldIsMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertFalse(settings.expandTerminalWhenActionsRun)
    }

    func testDecodeDefaultsMaxTerminalSessionsWhenFieldIsMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.maxTerminalSessions, 10)
    }

    func testDecodeDefaultsContextManagementWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertTrue(settings.contextManagementEnabled)
        XCTAssertEqual(settings.sessionHandoffWindowPercentage, AppSettings.defaultSessionHandoffWindowPercentage)
        XCTAssertTrue(settings.handoffContextCustomizationEnabled)
        XCTAssertEqual(settings.sessionHandoffPrompt, AppSettings.defaultSessionHandoffPrompt)
    }

    func testDecodeDefaultsEnterBehaviorWhenFieldIsMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.defaultEnterBehavior, .queue)
    }

    func testDecodeDefaultsEnterBehaviorWhenFieldIsInvalid() throws {
        let json = Data(#"{"defaultEnterBehavior":"send"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.defaultEnterBehavior, .queue)
    }

    func testDecodeMigratesLegacyBranchPrefixToIncludeSeparator() throws {
        let json = Data(#"{"branchPrefix":"feature"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.branchPrefix, "feature/")
    }

    func testDecodePreservesCurrentBranchPrefixLiterally() throws {
        let json = Data(#"{"settingsSchemaVersion":1,"branchPrefix":"feature"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.branchPrefix, "feature")
    }

    func testDecodePreservesEmptyBranchPrefix() throws {
        let json = Data(#"{"branchPrefix":""}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.branchPrefix, "")
    }

    func testNormalizedDropsProviderConfigWithOnlyLegacyFields() throws {
        let json = Data(
            #"""
            {
              "providerConfigs": {
                "claude": {
                  "cli": "/usr/local/bin/claude",
                  "resumeFlag": "--resume",
                  "autoApproveFlag": "--dangerously-skip-permissions",
                  "initialPromptFlag": "--prompt",
                  "env": {
                    "ALVEARY_FIXTURE": "1"
                  }
                },
                "other": {
                  "extraArgs": " --verbose "
                }
              }
            }
            """#.utf8
        )
        let settings = try JSONDecoder().decode(AppSettings.self, from: json).normalized()

        XCTAssertNil(settings.providerConfigs["claude"])
        XCTAssertEqual(settings.providerConfigs["other"], ProviderCustomConfig(extraArgs: "--verbose"))
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

    func testNormalizedClampsMaxTerminalSessionsToSupportedRange() {
        var lowSettings = AppSettings()
        lowSettings.maxTerminalSessions = 0

        var highSettings = AppSettings()
        highSettings.maxTerminalSessions = 500

        XCTAssertEqual(lowSettings.normalized().maxTerminalSessions, AppSettings.supportedMaxTerminalSessionsRange.lowerBound)
        XCTAssertEqual(highSettings.normalized().maxTerminalSessions, AppSettings.supportedMaxTerminalSessionsRange.upperBound)
    }

    func testNormalizedClampsFontSizesAndRestoresDefaultFontFamily() {
        var lowSettings = AppSettings()
        lowSettings.codeFontFamily = "  \n  "
        lowSettings.codeFontSize = 1
        lowSettings.chatFontSize = 1

        var highSettings = AppSettings()
        highSettings.codeFontFamily = "  Monaco  "
        highSettings.codeFontSize = 100
        highSettings.chatFontSize = 100

        let normalizedLow = lowSettings.normalized()
        let normalizedHigh = highSettings.normalized()

        XCTAssertEqual(normalizedLow.codeFontFamily, AppSettings.defaultCodeFontFamily)
        XCTAssertEqual(normalizedLow.codeFontSize, AppSettings.supportedCodeFontSizeRange.lowerBound)
        XCTAssertEqual(normalizedLow.chatFontSize, AppSettings.supportedChatFontSizeRange.lowerBound)
        XCTAssertEqual(normalizedHigh.codeFontFamily, "Monaco")
        XCTAssertEqual(normalizedHigh.codeFontSize, AppSettings.supportedCodeFontSizeRange.upperBound)
        XCTAssertEqual(normalizedHigh.chatFontSize, AppSettings.supportedChatFontSizeRange.upperBound)
    }

    func testNormalizedClampsSessionHandoffWindowPercentageToSupportedRangeAndStep() {
        var lowSettings = AppSettings()
        lowSettings.sessionHandoffWindowPercentage = 0

        var highSettings = AppSettings()
        highSettings.sessionHandoffWindowPercentage = 500

        var steppedSettings = AppSettings()
        steppedSettings.sessionHandoffWindowPercentage = 92

        XCTAssertEqual(
            lowSettings.normalized().sessionHandoffWindowPercentage,
            AppSettings.minimumSessionHandoffWindowPercentage
        )
        XCTAssertEqual(
            highSettings.normalized().sessionHandoffWindowPercentage,
            AppSettings.supportedHandoffPercentageRange.upperBound
        )
        XCTAssertEqual(
            steppedSettings.normalized().sessionHandoffWindowPercentage,
            AppSettings.defaultSessionHandoffWindowPercentage
        )
    }

    func testNormalizedRestoresDefaultSessionHandoffPromptWhenPromptIsEmpty() {
        var settings = AppSettings()
        settings.sessionHandoffPrompt = "  \n  "

        XCTAssertEqual(settings.normalized().sessionHandoffPrompt, AppSettings.defaultSessionHandoffPrompt)
    }

}
