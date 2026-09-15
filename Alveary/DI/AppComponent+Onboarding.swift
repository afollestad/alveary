@MainActor
extension AppComponent {
    var onboardingDependencyService: any OnboardingDependencyService {
        shared {
            DefaultOnboardingDependencyService(
                gitHubCLI: gitHubCLIService,
                harnessDetection: harnessDetectionService,
                agentRegistry: agentRegistry,
                shell: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }
}
