import AgentCLIKit
import NeedleFoundation

@MainActor
extension AppComponent {
    /// Merges every feature that answers on the shared `alveary_host` server. Enroll a new
    /// feature here and in `AlvearyHostToolCatalog.featureCatalogs`.
    ///
    /// The feature list is a closure because this dispatcher is constructed while
    /// `agentCLIKitRuntime` is being built; resolving a feature that reaches `agentsManager`
    /// eagerly would recurse back through this getter.
    var hostToolDispatcher: HostToolDispatcher {
        return shared {
            HostToolDispatcher(features: { [self.scheduledTaskHostToolService, self.threadHostToolService] })
        }
    }

    var hostToolHandling: AgentCLIKit.AgentHostToolHandling {
        hostToolDispatcher.handling
    }
}
