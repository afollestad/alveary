import AgentCLIKit
import Foundation

/// How `create_thread` settles harness, model, effort, and permission mode: an omitted harness,
/// model, or effort inherits the caller's own before falling back to the user's defaults —
/// "create a thread" usually means "one like this one" — while every *requested* value is
/// validated against what this Mac can actually run, with each rejection naming the valid values
/// so the model can correct itself instead of guessing again.
extension ThreadHostToolService {
    /// Resolves everything an omitted setting falls back to: the caller's own settings, the user's
    /// defaults, the harness the request settled on, and that harness's model options. The
    /// caller's settings are snapshotted before the resolver's suspension — SwiftData models must
    /// not be read across it.
    func resolvedSettingDefaults(
        source: HostToolCallSource,
        fallbackHarness: String,
        requestedHarness: String?
    ) async throws -> ThreadSettingDefaults {
        let sourceSettings = ThreadHostToolSourceSettings(
            harness: source.conversation.harness ?? fallbackHarness,
            model: source.thread.model,
            effort: source.thread.effort
        )
        let resolution = await resolvedThreadDefaults(settings: settingsService.current)
        let harness = try validatedHarness(requestedHarness, source: sourceSettings, resolution: resolution)
        return ThreadSettingDefaults(
            source: sourceSettings,
            resolution: resolution,
            harness: harness,
            options: await modelOptions(for: harness, resolution: resolution)
        )
    }

    func resolvedThreadDefaults(settings: AppSettings) async -> ThreadDefaultResolution {
        if let harnessDiscovery {
            return await ThreadDefaultResolver.resolve(
                settings: settings,
                harnessDiscovery: harnessDiscovery
            )
        }
        return ThreadDefaultResolver.resolve(
            settings: settings,
            harnessOrdering: AppSettings.supportedHarnessIDs,
            harnessStatuses: [:],
            allowStaticFallback: true
        )
    }

    /// The model options a requested model and effort validate against. The defaults resolution
    /// only carries the *default* harness's options, so a request naming a different ready
    /// harness asks discovery for that harness's own list — otherwise a valid model on the
    /// non-default harness would be falsely rejected.
    func modelOptions(
        for harness: String,
        resolution: ThreadDefaultResolution
    ) async -> [AgentCLIKit.AgentModelOption] {
        if harness == resolution.harnessID, !resolution.modelOptions.isEmpty {
            return resolution.modelOptions
        }
        if let harnessDiscovery,
           let harnessID = AgentCLIKit.AgentHarnessID(rawValue: harness) {
            let discovered = await harnessDiscovery.modelOptions(for: harnessID)
            if !discovered.isEmpty {
                return discovered
            }
        }
        return ThreadDefaultResolver.modelOptions(for: harness, harnessStatuses: [:])
    }

    /// An omitted harness means the caller's own — the harness executing this very call — and
    /// only falls back to the user's default if discovery no longer reports the caller's as ready.
    func validatedHarness(
        _ requested: String?,
        source: ThreadHostToolSourceSettings,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        guard let requested else {
            if resolution.readyHarnessIDs.contains(source.harness) {
                return source.harness
            }
            guard let harnessID = resolution.harnessID else {
                throw ThreadHostToolServiceError.noReadyHarness
            }
            return harnessID
        }
        guard resolution.readyHarnessIDs.contains(requested) else {
            throw ThreadHostToolServiceError.harnessNotReady(
                harnessID: requested,
                ready: resolution.readyHarnessIDs
            )
        }
        return requested
    }

    /// `nil` means "the harness's default model". An omitted `model` inherits the caller's own
    /// while the harness matches — trusted host state a running thread already uses, so it is
    /// deliberately not re-validated against live options, which change independently of it. A
    /// request naming a different harness cannot inherit and falls back to the user's settings.
    func validatedModel(
        _ requested: String?,
        defaults: ThreadSettingDefaults
    ) throws -> String? {
        guard let requested else {
            if defaults.harness == defaults.source.harness {
                return normalizedInheritedModel(defaults.source.model)
            }
            return defaults.harness == defaults.resolution.harnessID ? defaults.resolution.storedThreadModel : nil
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
            if defaults.harness == defaults.source.harness, !defaults.source.effort.isEmpty {
                inherited = defaults.source.effort
            } else if defaults.harness == defaults.resolution.harnessID {
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
        harness: String,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        let supported = AppSettings.supportedPermissionModes(forHarness: harness)
        guard let requested else {
            let inherited = harness == resolution.harnessID ? resolution.permissionMode : ""
            return supported.contains(inherited)
                ? inherited
                : AppSettings.defaultPermissionMode(forHarness: harness)
        }
        guard supported.contains(requested) else {
            throw ThreadHostToolServiceError.permissionModeUnavailable(
                mode: requested,
                harnessID: harness,
                supported: supported
            )
        }
        return requested
    }
}

private extension ThreadHostToolService {
    /// The caller's "harness default" stays exactly that: `nil`, an empty string, and the UI's
    /// `"default"` sentinel all read as nil rather than resolving to the settings model.
    func normalizedInheritedModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty, model != AppSettings.defaultModelValue else {
            return nil
        }
        return model
    }
}

/// Everything an omitted setting resolves against, bundled because the validators consult all of
/// it: the caller's own settings, the user's defaults, the harness the request settled on, and
/// that harness's model options.
struct ThreadSettingDefaults {
    let source: ThreadHostToolSourceSettings
    let resolution: ThreadDefaultResolution
    let harness: String
    let options: [AgentCLIKit.AgentModelOption]
}
