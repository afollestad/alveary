import AgentCLIKit
import Foundation

struct ThreadDefaultResolution: Equatable {
    let harnessID: String?
    let storedThreadModel: String?
    let permissionMode: String
    let effort: String
    let readyHarnessIDs: [String]
    let modelOptions: [AgentCLIKit.AgentModelOption]

    var hasReadyHarness: Bool {
        harnessID != nil
    }
}

enum ThreadDefaultResolver {
    static func resolve(
        settings: AppSettings,
        harnessOrdering: [String],
        harnessStatuses: [String: AgentCLIKit.AgentHarnessStatus],
        allowStaticFallback: Bool = false
    ) -> ThreadDefaultResolution {
        let orderedHarnessIDs = orderedSupportedHarnessIDs(harnessOrdering)
        let readyHarnessIDs = orderedHarnessIDs.filter { harnessID in
            guard settings.isHarnessEnabled(harnessID) else {
                return false
            }
            guard let status = harnessStatuses[harnessID] else {
                return allowStaticFallback
            }
            return isReadyHarness(harnessID: harnessID, settings: settings, status: status)
        }

        let resolvedHarnessID: String? = readyHarnessIDs.contains(settings.defaultHarness)
            ? settings.defaultHarness
            : readyHarnessIDs.first
        guard let harnessID = resolvedHarnessID else {
            return ThreadDefaultResolution(
                harnessID: nil,
                storedThreadModel: nil,
                permissionMode: settings.permissionMode,
                effort: AppSettings.normalizedEffortLevel(settings.effort),
                readyHarnessIDs: readyHarnessIDs,
                modelOptions: []
            )
        }

        let options = modelOptions(for: harnessID, harnessStatuses: harnessStatuses)
        let storedModel = normalizedStoredModel(settings.defaultModel, options: options)
        let permissionMode = normalizedPermissionMode(settings.permissionMode, harnessID: harnessID)
        let effort = AgentModelOptionSelection.normalizedEffort(
            settings.effort,
            options: options,
            selectedModel: storedModel
        )

        return ThreadDefaultResolution(
            harnessID: harnessID,
            storedThreadModel: storedModel == AppSettings.defaultModelValue ? nil : storedModel,
            permissionMode: permissionMode,
            effort: effort,
            readyHarnessIDs: readyHarnessIDs,
            modelOptions: options
        )
    }

    static func resolve(
        settings: AppSettings,
        harnessDiscovery: any AgentCLIKit.AgentHarnessDiscoveryService
    ) async -> ThreadDefaultResolution {
        async let ordering = harnessDiscovery.stableHarnessOrdering()
        async let statuses = harnessDiscovery.harnessStatuses(projectURL: nil)
        let resolvedOrdering = await ordering
        let resolvedStatuses = await statuses
        return resolve(
            settings: settings,
            harnessOrdering: resolvedOrdering.map(\.rawValue),
            harnessStatuses: Dictionary(uniqueKeysWithValues: resolvedStatuses.map { ($0.key.rawValue, $0.value) })
        )
    }

    static func modelOptions(
        for harnessID: String,
        harnessStatuses: [String: AgentCLIKit.AgentHarnessStatus]
    ) -> [AgentCLIKit.AgentModelOption] {
        if let options = harnessStatuses[harnessID]?.modelOptions, !options.isEmpty {
            return options
        }
        guard let id = AgentCLIKit.AgentHarnessID(rawValue: harnessID) else {
            return []
        }
        return AgentCLIKit.AgentDefaultModelOptions.staticOptions(for: id)
    }

    static func orderedSupportedHarnessIDs(_ harnessOrdering: [String]) -> [String] {
        let ordered = harnessOrdering.isEmpty ? AppSettings.supportedHarnessIDs : harnessOrdering
        let supported = ordered.filter(AppSettings.supportedHarnessIDs.contains)
        return supported.isEmpty ? AppSettings.supportedHarnessIDs : supported
    }

    static func isReadyHarness(
        harnessID: String,
        settings: AppSettings,
        status: AgentCLIKit.AgentHarnessStatus
    ) -> Bool {
        settings.isHarnessEnabled(harnessID) && status.isEnabled && status.isInstalled && status.isSetupReady
    }

    private static func normalizedStoredModel(
        _ model: String,
        options: [AgentCLIKit.AgentModelOption]
    ) -> String {
        guard let option = AgentModelOptionSelection.option(in: options, matching: model) else {
            return AppSettings.defaultModelValue
        }
        return AgentModelOptionSelection.storedModelValue(for: option)
    }

    private static func normalizedPermissionMode(_ mode: String, harnessID: String) -> String {
        let supportedModes = AppSettings.supportedPermissionModes(forHarness: harnessID)
        return supportedModes.contains(mode) ? mode : AppSettings.defaultPermissionMode(forHarness: harnessID)
    }
}
