@testable import Alveary

extension ContentView {
    /// Test-only, so production cannot build view models in a `ContentView` init; `ContentViewHost`
    /// owns why.
    init(component: AppComponent, appState: AppState) {
        let dependencies = ContentViewDependencies.resolve(component)
        self.init(
            dependencies: dependencies,
            bootstrapState: ContentView.makeBootstrapState(dependencies: dependencies, appState: appState),
            appState: appState
        )
    }
}
