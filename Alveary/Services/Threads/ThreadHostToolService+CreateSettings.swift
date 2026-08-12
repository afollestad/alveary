import AgentCLIKit
import Foundation

/// How `create_thread` settles provider, model, effort, and permission mode: an omitted provider,
/// model, or effort inherits the caller's own before falling back to the user's defaults —
/// "create a thread" usually means "one like this one" — while every *requested* value is
/// validated against what this Mac can actually run, with each rejection naming the valid values
/// so the model can correct itself instead of guessing again.
extension ThreadHostToolService {
    /// Resolves everything an omitted setting falls back to: the caller's own settings, the user's
    /// defaults, the provider the request settled on, and that provider's model options. The
    /// caller's settings are snapshotted before the resolver's suspension — SwiftData models must
    /// not be read across it.
    func resolvedSettingDefaults(
        source: HostToolCallSource,
        fallbackProvider: String,
        requestedProvider: String?
    ) async throws -> ThreadSettingDefaults {
        let sourceSettings = ThreadHostToolSourceSettings(
            provider: source.conversation.provider ?? fallbackProvider,
            model: source.thread.model,
            effort: source.thread.effort
        )
        let resolution = await resolvedThreadDefaults(settings: settingsService.current)
        let provider = try validatedProvider(requestedProvider, source: sourceSettings, resolution: resolution)
        return ThreadSettingDefaults(
            source: sourceSettings,
            resolution: resolution,
            provider: provider,
            options: await modelOptions(for: provider, resolution: resolution)
        )
    }

    func resolvedThreadDefaults(settings: AppSettings) async -> ThreadDefaultResolution {
        if let providerDiscovery {
            return await ThreadDefaultResolver.resolve(
                settings: settings,
                providerDiscovery: providerDiscovery
            )
        }
        return ThreadDefaultResolver.resolve(
            settings: settings,
            providerOrdering: AppSettings.supportedProviderIDs,
            providerStatuses: [:],
            allowStaticFallback: true
        )
    }

    /// The model options a requested model and effort validate against. The defaults resolution
    /// only carries the *default* provider's options, so a request naming a different ready
    /// provider asks discovery for that provider's own list — otherwise a valid model on the
    /// non-default provider would be falsely rejected.
    func modelOptions(
        for provider: String,
        resolution: ThreadDefaultResolution
    ) async -> [AgentCLIKit.AgentModelOption] {
        if provider == resolution.providerID, !resolution.modelOptions.isEmpty {
            return resolution.modelOptions
        }
        if let providerDiscovery,
           let providerID = AgentCLIKit.AgentProviderID(rawValue: provider) {
            let discovered = await providerDiscovery.modelOptions(for: providerID)
            if !discovered.isEmpty {
                return discovered
            }
        }
        return ThreadDefaultResolver.modelOptions(for: provider, providerStatuses: [:])
    }

    /// An omitted provider means the caller's own — the provider executing this very call — and
    /// only falls back to the user's default if discovery no longer reports the caller's as ready.
    func validatedProvider(
        _ requested: String?,
        source: ThreadHostToolSourceSettings,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        guard let requested else {
            if resolution.readyProviderIDs.contains(source.provider) {
                return source.provider
            }
            guard let providerID = resolution.providerID else {
                throw ThreadHostToolServiceError.noReadyProvider
            }
            return providerID
        }
        guard resolution.readyProviderIDs.contains(requested) else {
            throw ThreadHostToolServiceError.providerNotReady(
                providerID: requested,
                ready: resolution.readyProviderIDs
            )
        }
        return requested
    }

    /// `nil` means "the provider's default model". An omitted `model` inherits the caller's own
    /// while the provider matches — trusted host state a running thread already uses, so it is
    /// deliberately not re-validated against live options, which change independently of it. A
    /// request naming a different provider cannot inherit and falls back to the user's settings.
    func validatedModel(
        _ requested: String?,
        defaults: ThreadSettingDefaults
    ) throws -> String? {
        guard let requested else {
            if defaults.provider == defaults.source.provider {
                return normalizedInheritedModel(defaults.source.model)
            }
            return defaults.provider == defaults.resolution.providerID ? defaults.resolution.storedThreadModel : nil
        }
        guard let option = AgentModelOptionSelection.option(in: defaults.options, matching: requested) else {
            throw ThreadHostToolServiceError.modelUnavailable(model: requested)
        }
        let stored = AgentModelOptionSelection.storedModelValue(for: option)
        return stored == AppSettings.defaultModelValue ? nil : stored
    }

    func validatedEffort(
        _ requested: String?,
        defaults: ThreadSettingDefaults,
        model: String?
    ) throws -> String {
        guard let requested else {
            let inherited: String
            if defaults.provider == defaults.source.provider, !defaults.source.effort.isEmpty {
                inherited = defaults.source.effort
            } else if defaults.provider == defaults.resolution.providerID {
                inherited = defaults.resolution.effort
            } else {
                inherited = AppSettings.defaultEffortLevel
            }
            // Normalization coerces an effort the chosen model no longer supports to its default.
            return AgentModelOptionSelection.normalizedEffort(inherited, options: defaults.options, selectedModel: model)
        }
        let supported = AgentModelOptionSelection.effortOptions(in: defaults.options, selectedModel: model)
        guard supported.isEmpty || supported.contains(where: { $0.value == requested }) else {
            throw ThreadHostToolServiceError.effortUnavailable(
                effort: requested,
                supported: supported.map(\.value)
            )
        }
        return requested
    }

    func validatedPermissionMode(
        _ requested: String?,
        provider: String,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        let supported = AppSettings.supportedPermissionModes(forProvider: provider)
        guard let requested else {
            let inherited = provider == resolution.providerID ? resolution.permissionMode : ""
            return supported.contains(inherited)
                ? inherited
                : AppSettings.defaultPermissionMode(forProvider: provider)
        }
        guard supported.contains(requested) else {
            throw ThreadHostToolServiceError.permissionModeUnavailable(
                mode: requested,
                providerID: provider,
                supported: supported
            )
        }
        return requested
    }
}

private extension ThreadHostToolService {
    /// The caller's "provider default" stays exactly that: `nil`, an empty string, and the UI's
    /// `"default"` sentinel all read as nil rather than resolving to the settings model.
    func normalizedInheritedModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty, model != AppSettings.defaultModelValue else {
            return nil
        }
        return model
    }
}

/// Everything an omitted setting resolves against, bundled because the validators consult all of
/// it: the caller's own settings, the user's defaults, the provider the request settled on, and
/// that provider's model options.
struct ThreadSettingDefaults {
    let source: ThreadHostToolSourceSettings
    let resolution: ThreadDefaultResolution
    let provider: String
    let options: [AgentCLIKit.AgentModelOption]
}
