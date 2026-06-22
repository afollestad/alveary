import AgentCLIKit
import Foundation

struct ThreadDefaultResolution: Equatable {
    let providerID: String?
    let storedThreadModel: String?
    let permissionMode: String
    let effort: String
    let readyProviderIDs: [String]
    let modelOptions: [AgentCLIKit.AgentModelOption]

    var hasReadyProvider: Bool {
        providerID != nil
    }
}

enum ThreadDefaultResolver {
    static func resolve(
        settings: AppSettings,
        providerOrdering: [String],
        providerStatuses: [String: AgentCLIKit.AgentProviderStatus],
        allowStaticFallback: Bool = false
    ) -> ThreadDefaultResolution {
        let orderedProviderIDs = orderedSupportedProviderIDs(providerOrdering)
        let readyProviderIDs = orderedProviderIDs.filter { providerID in
            guard settings.isProviderEnabled(providerID) else {
                return false
            }
            guard let status = providerStatuses[providerID] else {
                return allowStaticFallback
            }
            return isReadyProvider(providerID: providerID, settings: settings, status: status)
        }

        let resolvedProviderID: String? = readyProviderIDs.contains(settings.defaultProvider)
            ? settings.defaultProvider
            : readyProviderIDs.first
        guard let providerID = resolvedProviderID else {
            return ThreadDefaultResolution(
                providerID: nil,
                storedThreadModel: nil,
                permissionMode: settings.permissionMode,
                effort: AppSettings.normalizedEffortLevel(settings.effort),
                readyProviderIDs: readyProviderIDs,
                modelOptions: []
            )
        }

        let options = modelOptions(for: providerID, providerStatuses: providerStatuses)
        let storedModel = normalizedStoredModel(settings.defaultModel, options: options)
        let permissionMode = normalizedPermissionMode(settings.permissionMode, providerID: providerID)
        let effort = AgentModelOptionSelection.normalizedEffort(
            settings.effort,
            options: options,
            selectedModel: storedModel
        )

        return ThreadDefaultResolution(
            providerID: providerID,
            storedThreadModel: storedModel == AppSettings.defaultModelValue ? nil : storedModel,
            permissionMode: permissionMode,
            effort: effort,
            readyProviderIDs: readyProviderIDs,
            modelOptions: options
        )
    }

    static func resolve(
        settings: AppSettings,
        providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    ) async -> ThreadDefaultResolution {
        async let ordering = providerDiscovery.stableProviderOrdering()
        async let statuses = providerDiscovery.providerStatuses(projectURL: nil)
        let resolvedOrdering = await ordering
        let resolvedStatuses = await statuses
        return resolve(
            settings: settings,
            providerOrdering: resolvedOrdering.map(\.rawValue),
            providerStatuses: Dictionary(uniqueKeysWithValues: resolvedStatuses.map { ($0.key.rawValue, $0.value) })
        )
    }

    static func modelOptions(
        for providerID: String,
        providerStatuses: [String: AgentCLIKit.AgentProviderStatus]
    ) -> [AgentCLIKit.AgentModelOption] {
        if let options = providerStatuses[providerID]?.modelOptions, !options.isEmpty {
            return options
        }
        guard let id = AgentCLIKit.AgentProviderID(rawValue: providerID) else {
            return []
        }
        return AgentCLIKit.AgentDefaultModelOptions.providerDefault(for: id)
    }

    static func orderedSupportedProviderIDs(_ providerOrdering: [String]) -> [String] {
        let ordered = providerOrdering.isEmpty ? AppSettings.supportedProviderIDs : providerOrdering
        let supported = ordered.filter(AppSettings.supportedProviderIDs.contains)
        return supported.isEmpty ? AppSettings.supportedProviderIDs : supported
    }

    static func isReadyProvider(
        providerID: String,
        settings: AppSettings,
        status: AgentCLIKit.AgentProviderStatus
    ) -> Bool {
        settings.isProviderEnabled(providerID) && status.isEnabled && status.isInstalled && status.isSetupReady
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

    private static func normalizedPermissionMode(_ mode: String, providerID: String) -> String {
        let supportedModes = AppSettings.supportedPermissionModes(forProvider: providerID)
        return supportedModes.contains(mode) ? mode : AppSettings.defaultPermissionMode(forProvider: providerID)
    }
}
