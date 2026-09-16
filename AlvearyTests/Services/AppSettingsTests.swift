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

    func testMenuBarIconIsShownByDefault() {
        XCTAssertTrue(AppSettings().showsMenuBarIcon)
    }

    func testDefaultLastSettingsPageIsHarnesses() {
        XCTAssertEqual(AppSettings().lastSettingsPage, .harnesses)
    }

    func testSettingsPagesAreInVisibleAlphabeticalOrder() {
        XCTAssertEqual(
            AppSettings.SettingsPage.allCases.map(\.rawValue),
            [
                "interface", "appShots", "git", "handoff", "agents",
                "menuBar", "notifications", "terminal", "threads", "appUpdates"
            ]
        )
    }

    func testDefaultEnterBehaviorIsQueue() {
        XCTAssertEqual(AppSettings().defaultEnterBehavior, .queue)
    }

    func testDefaultFontSizes() {
        let settings = AppSettings()

        XCTAssertEqual(settings.codeFontSize, 12)
        XCTAssertEqual(settings.chatFontSize, 13)
    }

    func testDefaultContextManagementSettings() {
        let settings = AppSettings()

        XCTAssertFalse(settings.contextManagementEnabled)
        XCTAssertEqual(settings.sessionHandoffWindowPercentage, AppSettings.defaultSessionHandoffWindowPercentage)
        XCTAssertTrue(settings.handoffSteeringEnabled)
        XCTAssertEqual(settings.handoffSteeringCountdownSeconds, AppSettings.defaultHandoffSteeringCountdownSeconds)
        XCTAssertEqual(settings.handoffPromptSendCountdownSeconds, AppSettings.defaultHandoffPromptSendCountdownSeconds)
        XCTAssertTrue(settings.handoffContextCustomizationEnabled)
        XCTAssertTrue(settings.sessionHandoffPrompt.hasPrefix("Turn the current session into a prompt"))
        XCTAssertTrue(settings.sessionHandoffPrompt.contains("existing `AGENTS.md` context"))
        XCTAssertFalse(settings.sessionHandoffPrompt.contains("name: session-handoff"))
    }

    func testDefaultGitCommitSettings() {
        let settings = AppSettings()

        XCTAssertTrue(settings.gitCommitIncludeUnstagedChanges)
        XCTAssertTrue(settings.commitMessageGenerationPrompt.hasPrefix("Generate a Git commit message"))
        XCTAssertTrue(
            settings.commitMessageGenerationPrompt.contains(
                "Consider any existing project level or global level commit message guidelines."
            )
        )
        XCTAssertTrue(
            settings.commitMessageGenerationPrompt.contains(
                "Wrap file names, class names, function names, variable names, or other code tokens with single ticks (`)."
            )
        )
        XCTAssertTrue(settings.commitMessageGenerationPrompt.contains("Co-authored-by: Claude <noreply@anthropic.com>"))
        XCTAssertTrue(settings.commitMessageGenerationPrompt.contains("Co-authored-by: Codex <noreply@openai.com>"))
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

    func testDecodePreservesLastSettingsPage() throws {
        let cases: [(String, AppSettings.SettingsPage)] = [("git", .git), ("agents", .harnesses)]
        for (storedValue, expectedPage) in cases {
            let json = try JSONEncoder().encode(["lastSettingsPage": storedValue])
            let settings = try JSONDecoder().decode(AppSettings.self, from: json)
            XCTAssertEqual(settings.lastSettingsPage, expectedPage)

            let encoded = try JSONEncoder().encode(settings)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertEqual(object["lastSettingsPage"] as? String, storedValue)
        }
    }

    func testDecodeDefaultsLastSettingsPageWhenFieldIsInvalid() throws {
        let json = Data(#"{"lastSettingsPage":"advanced","theme":"dark"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.lastSettingsPage, .harnesses)
        XCTAssertEqual(settings.theme, "dark")
    }

    func testDecodeDefaultsContextManagementWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertFalse(settings.contextManagementEnabled)
        XCTAssertEqual(settings.sessionHandoffWindowPercentage, AppSettings.defaultSessionHandoffWindowPercentage)
        XCTAssertTrue(settings.handoffSteeringEnabled)
        XCTAssertEqual(settings.handoffSteeringCountdownSeconds, AppSettings.defaultHandoffSteeringCountdownSeconds)
        XCTAssertEqual(settings.handoffPromptSendCountdownSeconds, AppSettings.defaultHandoffPromptSendCountdownSeconds)
        XCTAssertTrue(settings.handoffContextCustomizationEnabled)
        XCTAssertEqual(settings.sessionHandoffPrompt, AppSettings.defaultSessionHandoffPrompt)
    }

    func testDecodeDefaultsGitCommitSettingsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.commitMessageGenerationPrompt, AppSettings.defaultCommitMessageGenerationPrompt)
        XCTAssertEqual(settings.pullRequestGenerationPrompt, AppSettings.defaultPullRequestGenerationPrompt)
        XCTAssertTrue(settings.gitCommitIncludeUnstagedChanges)
    }

    func testDefaultPullRequestGenerationPromptStatesTheResponseContract() {
        let settings = AppSettings()

        XCTAssertTrue(settings.pullRequestGenerationPrompt.hasPrefix("Generate a pull request title"))
        XCTAssertTrue(
            settings.pullRequestGenerationPrompt.contains("The first line of your response is the pull request title")
        )
    }

    func testNormalizationRestoresAnEmptyPullRequestGenerationPrompt() {
        var settings = AppSettings()
        settings.pullRequestGenerationPrompt = "   "

        XCTAssertEqual(
            settings.normalized().pullRequestGenerationPrompt,
            AppSettings.defaultPullRequestGenerationPrompt
        )
    }

    func testDecodeDefaultsFontSizesWhenFieldsAreMissing() throws {
        let json = Data(#"{"theme":"dark"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.codeFontSize, 12)
        XCTAssertEqual(settings.chatFontSize, 13)
    }

    func testDecodePreservesExplicitStoredOldDefaultFontSizes() throws {
        let json = Data(
            #"""
            {
              "codeFontSize": 13,
              "chatFontSize": 14
            }
            """#.utf8
        )
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.codeFontSize, 13)
        XCTAssertEqual(settings.chatFontSize, 14)
    }

    func testDecodeDefaultsEnterBehaviorWhenFieldIsMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.defaultEnterBehavior, .queue)
    }

    func testDecodeDefaultsThreadCleanupActionWhenFieldIsMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.defaultThreadCleanupAction, .archive)
    }

    func testDecodeIgnoresLegacyDeleteKeyAction() throws {
        let json = Data(#"{"deleteKeyAction":"delete"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.defaultThreadCleanupAction, .archive)
    }

    func testDecodePreservesDefaultThreadCleanupAction() throws {
        let json = Data(#"{"defaultThreadCleanupAction":"delete"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.defaultThreadCleanupAction, .delete)
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

    func testLegacyHarnessConfigsAreIgnoredAndDroppedOnSave() throws {
        let legacyValues: [Any] = [
            ["claude": ["extraArgs": "--verbose", "cli": "/old/claude"], "opencode": ["extraArgs": "--bad 'quote"]],
            ["claude": ["extraArgs": 42]],
            "invalid legacy config"
        ]
        for legacyValue in legacyValues {
            let data = try JSONSerialization.data(withJSONObject: [
                "defaultProvider": "codex", "disabledProviderIDs": ["claude"],
                "branchPrefix": "custom/", "providerConfigs": legacyValue
            ])
            let settings = try JSONDecoder().decode(AppSettings.self, from: data).normalized()
            XCTAssertEqual(settings.defaultHarness, "codex")
            XCTAssertEqual(settings.disabledHarnessIDs, ["claude"])
            XCTAssertEqual(settings.branchPrefix, "custom/")
            let encoded = try JSONEncoder().encode(settings)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertNil(object["providerConfigs"])
            XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: encoded), settings)
        }
    }

    func testNormalizedPreservesDynamicDefaultModelID() {
        var settings = AppSettings()
        settings.defaultModel = "gpt-9"

        XCTAssertEqual(settings.normalized().defaultModel, "gpt-9")
    }

    func testNormalizedClampsBlankDefaultModelToSentinel() {
        var settings = AppSettings()
        settings.defaultModel = "  \n  "

        XCTAssertEqual(settings.normalized().defaultModel, AppSettings.defaultModelValue)
    }

    func testNormalizedPreservesLastSettingsPage() {
        var settings = AppSettings()
        settings.lastSettingsPage = .terminal

        XCTAssertEqual(settings.normalized().lastSettingsPage, .terminal)
    }

    func testSetHarnessTogglesSupportedHarnessEnablement() {
        var settings = AppSettings()

        settings.setHarness("codex", enabled: false)

        XCTAssertFalse(settings.isHarnessEnabled("codex"))

        settings.setHarness("codex", enabled: true)
        settings.setHarness("unknown", enabled: false)

        XCTAssertTrue(settings.isHarnessEnabled("codex"))
        XCTAssertFalse(settings.disabledHarnessIDs.contains("unknown"))
    }

    func testNormalizedFallsBackWhenDefaultHarnessIsDisabled() {
        var settings = AppSettings()
        settings.defaultHarness = "codex"
        settings.disabledHarnessIDs = ["codex"]

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.defaultHarness, "claude")
        XCTAssertTrue(normalized.isHarnessEnabled("claude"))
        XCTAssertFalse(normalized.isHarnessEnabled("codex"))
    }

    func testNormalizedKeepsAtLeastOneHarnessEnabled() {
        var settings = AppSettings()
        settings.disabledHarnessIDs = ["claude", "codex", "opencode", "unknown"]

        let normalized = settings.normalized()

        XCTAssertTrue(normalized.isHarnessEnabled("claude"))
        XCTAssertFalse(normalized.isHarnessEnabled("codex"))
        XCTAssertFalse(normalized.disabledHarnessIDs.contains("unknown"))
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

    func testNormalizedClampsHandoffCountdownSettingsToSupportedRanges() {
        var lowSettings = AppSettings()
        lowSettings.handoffSteeringCountdownSeconds = 0
        lowSettings.handoffPromptSendCountdownSeconds = -1

        var highSettings = AppSettings()
        highSettings.handoffSteeringCountdownSeconds = 500
        highSettings.handoffPromptSendCountdownSeconds = 500

        XCTAssertEqual(
            lowSettings.normalized().handoffSteeringCountdownSeconds,
            AppSettings.supportedHandoffSteeringCountdownRange.lowerBound
        )
        XCTAssertEqual(
            lowSettings.normalized().handoffPromptSendCountdownSeconds,
            AppSettings.supportedHandoffPromptSendCountdownRange.lowerBound
        )
        XCTAssertEqual(
            highSettings.normalized().handoffSteeringCountdownSeconds,
            AppSettings.supportedHandoffSteeringCountdownRange.upperBound
        )
        XCTAssertEqual(
            highSettings.normalized().handoffPromptSendCountdownSeconds,
            AppSettings.supportedHandoffPromptSendCountdownRange.upperBound
        )
    }

    func testNormalizedRestoresDefaultSessionHandoffPromptWhenPromptIsEmpty() {
        var settings = AppSettings()
        settings.sessionHandoffPrompt = "  \n  "

        XCTAssertEqual(settings.normalized().sessionHandoffPrompt, AppSettings.defaultSessionHandoffPrompt)
    }

    func testNormalizedRestoresDefaultCommitMessageGenerationPromptWhenPromptIsEmpty() {
        var settings = AppSettings()
        settings.commitMessageGenerationPrompt = "  \n  "

        XCTAssertEqual(
            settings.normalized().commitMessageGenerationPrompt,
            AppSettings.defaultCommitMessageGenerationPrompt
        )
    }

}
