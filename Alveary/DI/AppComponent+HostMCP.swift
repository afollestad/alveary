import AgentCLIKit
import NeedleFoundation

@MainActor
extension AppComponent {
    /// Merges every feature that answers on the shared `alveary_host` server. Enroll a new
    /// feature here and in `AlvearyHostToolCatalog.featureCatalogs`.
    var hostToolDispatcher: HostToolDispatcher {
        return shared {
            HostToolDispatcher(features: [scheduledTaskHostToolService])
        }
    }

    var hostToolHandling: AgentCLIKit.AgentHostToolHandling {
        hostToolDispatcher.handling
    }
}
