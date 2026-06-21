import Foundation
import XCTest

@testable import Alveary

@MainActor
func makeSettings(extraArgs: String? = nil) -> InMemorySettingsService {
    let providerConfig = ProviderCustomConfig(extraArgs: extraArgs)
    return InMemorySettingsService(current: AppSettings(providerConfigs: ["claude": providerConfig]))
}

@MainActor
func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(25),
    condition: @escaping () async throws -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout

    while clock.now < deadline {
        if try await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }

    throw WaitTimeoutError(description: description)
}

func firstEvent(
    from stream: AsyncStream<ConversationEvent>,
    description: String,
    timeout: Duration = .seconds(5)
) async throws -> ConversationEvent? {
    try await withThrowingTaskGroup(of: ConversationEvent?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw WaitTimeoutError(description: description)
        }

        defer { group.cancelAll() }
        return try await group.next() ?? nil
    }
}

let planModeHandoffPrefix = "You are currently in plan mode.\n\n"
let planModeHandoffInstruction =
    "Preserve the active plan/proposal, including whether it is pending, rejected, or ready to implement."

func assertPlanModeHandoffPromptOrder(
    _ hiddenPrompt: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let instructionRange = hiddenPrompt.range(of: planModeHandoffInstruction) else {
        XCTFail("Expected plan-mode handoff instruction", file: file, line: line)
        return
    }
    guard let configuredRange = hiddenPrompt.range(of: AppSettings.defaultSessionHandoffPrompt) else {
        XCTFail("Expected configured handoff prompt", file: file, line: line)
        return
    }
    XCTAssertLessThan(instructionRange.lowerBound, configuredRange.lowerBound, file: file, line: line)
}

struct WaitTimeoutError: LocalizedError {
    let description: String

    var errorDescription: String? {
        description
    }
}

actor StubProviderDetectionService: ProviderDetectionService {
    private let path: String?

    init(resolvedPath: String? = nil) {
        self.path = resolvedPath
    }

    func resolvedPath(for providerId: String) -> String? {
        path
    }

    func status(for providerId: String) -> ProviderStatus {
        .unchecked
    }

    func checkAllProviders() async {}

    func checkProvider(_ providerId: String) async {}
}

@MainActor
final class StubNotificationManager: NotificationManager {
    private(set) var handledEvents: [(event: ConversationEvent, conversationId: String)] = []

    func handleEvent(_ event: ConversationEvent, conversationId: String) {
        handledEvents.append((event, conversationId))
    }

    func markConversationRead(conversationId: String) {}
    func handleAppVisibilityChanged() {}
    func refreshBadgeCount() {}
    func setActiveConversationProvider(_ provider: @escaping @MainActor () -> String?) {}
}
