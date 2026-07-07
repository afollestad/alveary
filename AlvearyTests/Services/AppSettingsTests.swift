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

    func testDefaultLastSettingsPageIsAgents() {
        XCTAssertEqual(AppSettings().lastSettingsPage, .agents)
    }

    func testSettingsPagesAreInVisibleAlphabeticalOrder() {
        XCTAssertEqual(
            AppSettings.SettingsPage.allCases.map(\.rawValue),
            ["agents", "interface", "appShots", "git", "notifications", "terminal", "threads", "appUpdates"]
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
        let json = Data(#"{"lastSettingsPage":"git"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.lastSettingsPage, .git)
    }

    func testDecodeDefaultsLastSettingsPageWhenFieldIsInvalid() throws {
        let json = Data(#"{"lastSettingsPage":"advanced","theme":"dark"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.lastSettingsPage, .agents)
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
        XCTAssertTrue(settings.gitCommitIncludeUnstagedChanges)
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

    func testNormalizedPreservesSupportedDefaultModel() {
        var settings = AppSettings()
        settings.defaultModel = "opus"

        XCTAssertEqual(settings.normalized().defaultModel, "opus")
    }

    func testNormalizedPreservesLastSettingsPage() {
        var settings = AppSettings()
        settings.lastSettingsPage = .terminal

        XCTAssertEqual(settings.normalized().lastSettingsPage, .terminal)
    }

    func testSetProviderTogglesSupportedProviderEnablement() {
        var settings = AppSettings()

        settings.setProvider("codex", enabled: false)

        XCTAssertFalse(settings.isProviderEnabled("codex"))

        settings.setProvider("codex", enabled: true)
        settings.setProvider("unknown", enabled: false)

        XCTAssertTrue(settings.isProviderEnabled("codex"))
        XCTAssertFalse(settings.disabledProviderIDs.contains("unknown"))
    }

    func testNormalizedFallsBackWhenDefaultProviderIsDisabled() {
        var settings = AppSettings()
        settings.defaultProvider = "codex"
        settings.disabledProviderIDs = ["codex"]

        let normalized = settings.normalized()

        XCTAssertEqual(normalized.defaultProvider, "claude")
        XCTAssertTrue(normalized.isProviderEnabled("claude"))
        XCTAssertFalse(normalized.isProviderEnabled("codex"))
    }

    func testNormalizedKeepsAtLeastOneProviderEnabled() {
        var settings = AppSettings()
        settings.disabledProviderIDs = ["claude", "codex", "unknown"]

        let normalized = settings.normalized()

        XCTAssertTrue(normalized.isProviderEnabled("claude"))
        XCTAssertFalse(normalized.isProviderEnabled("codex"))
        XCTAssertFalse(normalized.disabledProviderIDs.contains("unknown"))
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
