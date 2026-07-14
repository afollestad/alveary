import Foundation

enum ClaudeNativeSchedulingLaunchPolicy {
    static func arguments(
        providerID: String,
        configuredArguments: [String]
    ) -> [String] {
        guard providerID == "claude" else {
            return configuredArguments
        }
        return argumentsDisallowingRemoteTrigger(configuredArguments)
    }

    static func environment(
        providerID: String,
        baseEnvironment: [String: String]
    ) -> [String: String] {
        guard providerID == "claude" else {
            return baseEnvironment
        }
        var environment = baseEnvironment
        environment["CLAUDE_CODE_DISABLE_CRON"] = "1"
        return environment
    }

    private static func argumentsDisallowingRemoteTrigger(_ configuredArguments: [String]) -> [String] {
        let optionNames = ["--disallowedTools", "--disallowed-tools"]
        let optionPrefixes = optionNames.map { "\($0)=" }
        let occurrences = configuredArguments.indices.filter { index in
            optionNames.contains(configuredArguments[index])
                || optionPrefixes.contains { configuredArguments[index].hasPrefix($0) }
        }

        for index in occurrences where configuredArguments[index].contains("=") {
            let values = configuredArguments[index].split(separator: "=", maxSplits: 1).last ?? ""
            if values.split(whereSeparator: { $0 == "," || $0.isWhitespace }).contains("RemoteTrigger") {
                return configuredArguments
            }
        }
        for index in occurrences where optionNames.contains(configuredArguments[index]) {
            let valueRange = (index + 1)..<configuredArguments.endIndex
            if configuredArguments[valueRange]
                .prefix(while: { !$0.hasPrefix("-") })
                .flatMap({ $0.split(whereSeparator: { $0 == "," || $0.isWhitespace }) })
                .contains("RemoteTrigger") {
                return configuredArguments
            }
        }

        guard let optionIndex = occurrences.last else {
            return configuredArguments + ["--disallowedTools", "RemoteTrigger"]
        }

        var arguments = configuredArguments
        if optionNames.contains(arguments[optionIndex]) {
            let insertionIndex = arguments[(optionIndex + 1)...]
                .firstIndex(where: { $0.hasPrefix("-") }) ?? arguments.endIndex
            arguments.insert("RemoteTrigger", at: insertionIndex)
        } else {
            arguments[optionIndex] += ",RemoteTrigger"
        }
        return arguments
    }
}
