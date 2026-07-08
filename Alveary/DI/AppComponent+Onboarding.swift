@MainActor
extension AppComponent {
    var onboardingDependencyService: any OnboardingDependencyService {
        shared {
            DefaultOnboardingDependencyService(
                gitHubCLI: gitHubCLIService,
                providerDetection: providerDetectionService,
                agentRegistry: agentRegistry,
                shell: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }
}
