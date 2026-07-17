import AppKit
import BlockInputKit

@testable import Alveary

struct VoiceBoundaryTestCase {
    let text: String
    let range: NSRange
    let replacement: String

    init(text: String, location: Int, length: Int = 0, replacement: String) {
        self.text = text
        range = NSRange(location: location, length: length)
        self.replacement = replacement
    }
}

@MainActor
final class ChatVoiceInputTestFixture {
    let service: FakeChatVoiceInputService
    let clock: TestChatVoiceInputClock
    let lifecycleController: VoiceInputLifecycleController
    var coordinator: ChatVoiceInputCoordinator!
    var controller: AppKitChatComposerEditorController!
    var editor: BlockInputView!
    var window: NSWindow!
    var flushCount = 0
    var announcements: [String] = []

    init(
        service: FakeChatVoiceInputService,
        clock: TestChatVoiceInputClock,
        lifecycleController: VoiceInputLifecycleController
    ) {
        self.service = service
        self.clock = clock
        self.lifecycleController = lifecycleController
    }

    var currentMarkdown: String {
        controller.bridgeController?.currentMarkdown() ?? ""
    }
}
