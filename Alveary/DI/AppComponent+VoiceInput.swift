import Foundation

@MainActor
extension AppComponent {
    var voiceInputService: any VoiceInputService {
        shared {
            DefaultVoiceInputService(
                modelsDirectory: storageProfile.voiceInputModelsDirectory,
                cacheOwnershipDirectory: storageProfile.appSupportDirectory
            )
        }
    }

    var voiceInputLifecycleController: VoiceInputLifecycleController {
        shared { VoiceInputLifecycleController(service: voiceInputService) }
    }
}
