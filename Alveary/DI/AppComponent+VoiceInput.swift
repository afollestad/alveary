import Foundation

@MainActor
extension AppComponent {
    var voiceInputService: any VoiceInputService {
        shared { DefaultVoiceInputService() }
    }

    var voiceInputLifecycleController: VoiceInputLifecycleController {
        shared { VoiceInputLifecycleController(service: voiceInputService) }
    }
}
