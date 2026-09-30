import SwiftUI

/// The main window's root: builds `ContentView`'s dependencies and view models once per window
/// hierarchy and hands every `ContentView` value the same instances.
///
/// Never build them as `ContentView` `@State` initial values. SwiftUI evaluates those on every init,
/// and the enclosing body observes whatever their constructors read, so every thread, conversation,
/// or settings write would rebuild all of them on the main thread. A discarded
/// `PullRequestReviewProposalCoordinator` would keep that loop going on its own while a review
/// proposal is pending, because its preview warm writes state its `init` reads.
///
/// The first pass here still observes those reads, so the next such write re-runs this body once;
/// later passes read only the stored instances and observe nothing.
struct ContentViewHost: View {
    let component: AppComponent
    let appState: AppState

    @State private var store = ContentViewRootStore()

    var body: some View {
        let root = store.resolve(component: component, appState: appState)
        ContentView(dependencies: root.dependencies, bootstrapState: root.bootstrapState, appState: appState)
    }
}

/// Deliberately not `@Observable`: filling it mid-body must publish nothing the host would observe.
@MainActor
private final class ContentViewRootStore {
    private var root: ContentViewRoot?

    func resolve(component: AppComponent, appState: AppState) -> ContentViewRoot {
        if let root {
            return root
        }
        let dependencies = ContentViewDependencies.resolve(component)
        let root = ContentViewRoot(
            dependencies: dependencies,
            bootstrapState: ContentView.makeBootstrapState(dependencies: dependencies, appState: appState)
        )
        self.root = root
        return root
    }
}

private struct ContentViewRoot {
    let dependencies: ContentViewDependencies
    let bootstrapState: ContentViewBootstrapState
}
