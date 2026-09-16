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
        sourceSettings: ThreadHostToolSourceSettings,
        requestedHarness: String?,
        projectURL: URL? = nil
    ) async throws -> ThreadSettingDefaults {
        let scopedStatuses: [AgentCLIKit.AgentHarnessID: AgentCLIKit.AgentHarnessStatus]?
        if let projectURL {
            scopedStatuses = await harnessDiscovery?.harnessStatuses(projectURL: projectURL)
        } else {
            scopedStatuses = nil
        }
        let resolution: ThreadDefaultResolution
        if let scopedStatuses {
            resolution = ThreadDefaultResolver.resolve(
                settings: settingsService.current, harnessOrdering: AppSettings.supportedHarnessIDs,
                harnessStatuses: Dictionary(uniqueKeysWithValues: scopedStatuses.map { ($0.key.rawValue, $0.value) })
            )
        } else {
            resolution = await resolvedThreadDefaults(settings: settingsService.current)
        }
        let harness = try validatedHarness(requestedHarness, source: sourceSettings, resolution: resolution)
        let options: [AgentCLIKit.AgentModelOption]
        if let scopedStatuses {
            options = scopedStatuses[.opencode]?.modelOptions ?? []
        } else {
            options = await modelOptions(for: harness, resolution: resolution)
        }
        return ThreadSettingDefaults(
            source: sourceSettings,
            resolution: resolution,
            harness: harness,
            options: options
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

    /// An omitted harness inherits the caller. OpenCode refuses unavailable inheritance rather than
    /// silently switching providers; existing harnesses retain their default fallback.
    func validatedHarness(
        _ requested: String?,
        source: ThreadHostToolSourceSettings,
        resolution: ThreadDefaultResolution
    ) throws -> String {
        guard let requested else {
            if resolution.readyHarnessIDs.contains(source.harness) {
                return source.harness
            }
            guard source.harness != "opencode" else {
                throw ThreadHostToolServiceError.harnessNotReady(
                    harnessID: source.harness,
                    ready: resolution.readyHarnessIDs
                )
            }
            guard let harnessID = resolution.harnessID else {
                throw ThreadHostToolServiceError.noReadyHarness
            }
            guard resolution.readyHarnessIDs.contains(harnessID) else {
                throw ThreadHostToolServiceError.harnessNotReady(harnessID: harnessID, ready: resolution.readyHarnessIDs)
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

    /// `nil` means the harness's default. Matching harnesses inherit the caller's model; OpenCode
    /// revalidates that selection so an unavailable provider is explicit before creating the task.
    /// Existing harnesses retain trusted inheritance; changing harnesses uses that harness's defaults.
    func validatedModel(
        _ requested: String?,
        defaults: ThreadSettingDefaults
    ) throws -> String? {
        guard let requested else {
            if defaults.harness == defaults.source.harness {
                let inherited = normalizedInheritedModel(defaults.source.model)
                if defaults.harness == "opencode", let inherited,
                   AgentModelOptionSelection.option(in: defaults.options, matching: inherited) == nil {
                    throw ThreadHostToolServiceError.modelUnavailable(model: inherited)
                }
                return inherited
            }
            let inherited = defaults.harness == defaults.resolution.harnessID ? defaults.resolution.storedThreadModel : nil
            if defaults.harness == "opencode", let inherited,
               AgentModelOptionSelection.option(in: defaults.options, matching: inherited) == nil {
                throw ThreadHostToolServiceError.modelUnavailable(model: inherited)
            }
            return inherited
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
        if defaults.harness == "opencode" {
            return try validatedOpenCodeEffort(requested, defaults: defaults, model: model)
        }
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
    func validatedOpenCodeEffort(_ requested: String?, defaults: ThreadSettingDefaults, model: String?) throws -> String {
        let inherited = defaults.harness == defaults.source.harness
            ? defaults.source.effort
            : (defaults.harness == defaults.resolution.harnessID ? defaults.resolution.effort : AppSettings.openCodeDefaultEffort)
        let effort = requested ?? (inherited.isEmpty ? AppSettings.openCodeDefaultEffort : inherited)
        let supported = [AppSettings.openCodeDefaultEffort] + AgentModelOptionSelection.effortOptions(
            in: defaults.options, selectedModel: model
        ).map(\.value).filter { $0 != AppSettings.openCodeDefaultEffort }
        guard supported.contains(effort) else {
            throw ThreadHostToolServiceError.effortUnavailable(effort: effort, supported: supported)
        }
        return effort
    }

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
