import XCTest
import SwiftUI

@testable import Alveary

@MainActor
final class SnapshotTests: XCTestCase {
    func testAppTextEditorInlineHint() {
        let text = "/review-github-pr "
        let selection = TextSelection(insertionPoint: text.endIndex)

        assertMacSnapshot(
            AppTextEditor(
                text: .constant(text),
                selection: .constant(selection),
                minHeight: 68,
                idealHeight: 68,
                maxHeight: 144,
                placeholder: "Ask anything, @ to add files, / for skills",
                cornerRadius: 18,
                horizontalPadding: 10,
                verticalPadding: 10,
                sizesToContent: true,
                textChips: ChatComposerTextSupport.composerTextChips(in:),
                inlineHint: AppTextEditorInlineHint(text: "[PR URL]")
            ),
            size: CGSize(width: 760, height: 120),
            named: "app_text_editor_inline_hint"
        )
    }

    func testChatComposerKeymapSheet() {
        let defaultEnterBehavior = AppSettings.defaultEnterBehavior
        let keymapView = AppKitChatComposerKeymapView()
        keymapView.configure(.init(supportsMidTurnSteering: true, defaultEnterBehavior: defaultEnterBehavior))
        let preferredSize = keymapView.preferredModalSize

        assertMacSnapshot(
            ChatComposerKeymapSheet(
                supportsMidTurnSteering: true,
                defaultEnterBehavior: defaultEnterBehavior
            ),
            size: CGSize(width: preferredSize.width, height: preferredSize.height),
            named: "chat_composer_keymap_sheet"
        )
    }

    func testSkillsScreenPopulated() async {
        let viewModel = SkillsViewModel(skillsService: SnapshotSkillsService())
        await viewModel.load()

        assertMacSnapshot(
            SkillsScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "skills_screen_populated"
        )
    }

    func testMCPScreenPopulated() async {
        let viewModel = MCPViewModel(mcpService: SnapshotMCPService())
        await viewModel.load()

        assertMacSnapshot(
            MCPScreen(viewModel: viewModel),
            size: CGSize(width: 1120, height: 900),
            named: "mcp_screen_populated"
        )
    }

}
