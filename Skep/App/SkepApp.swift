import SwiftUI

@main
struct SkepApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        _ = AppDI.resolver
    }

    var body: some Scene {
        Window("Skep", id: "main") {
            EmptyView()
        }
    }
}
