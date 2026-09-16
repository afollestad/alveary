import AgentCLIKit
import XCTest

@testable import Alveary

final class HarnessFeaturePolicyTests: XCTestCase {
    func testPendingDiscoveryDoesNotExposeOptionalFeatures() {
        let policy = HarnessFeaturePolicy(harnessID: "opencode", status: nil, selectedModel: "provider/vision")
        XCTAssertFalse(policy.supportsPlanMode)
        XCTAssertFalse(policy.supportsMidTurnSteering)
        XCTAssertFalse(policy.supportsContextCompaction)
        XCTAssertFalse(policy.supportsReasoning)
        XCTAssertFalse(policy.supportsLocalImageInput)
        XCTAssertFalse(policy.supportsAppShots)
    }

    func testOpenCodeImagesAndReasoningRequireTheExactConfirmedModel() {
        let text = AgentModelOption(harnessId: .opencode, id: "provider/text", model: "provider/text", label: "Text")
        let vision = AgentModelOption(
            harnessId: .opencode, id: "provider/vision", model: "provider/vision", label: "Vision",
            supportedEffortOptions: [.init(value: "deliberate", label: "Deliberate", description: "")],
            metadata: [OpenCodeModelMetadata.supportsImageInput: .bool(true)]
        )
        let status = AgentHarnessStatus(
            harnessId: .opencode, definition: OpenCodeHarnessDefinition.definition, modelOptions: [text, vision]
        )
        for selection in [nil, "default", "vision", "other/vision", "provider/text"] as [String?] {
            let policy = HarnessFeaturePolicy(harnessID: "opencode", status: status, selectedModel: selection)
            XCTAssertFalse(policy.supportsLocalImageInput, selection ?? "nil")
            XCTAssertFalse(policy.supportsAppShots, selection ?? "nil")
            XCTAssertFalse(policy.supportsReasoning, selection ?? "nil")
        }
        let policy = HarnessFeaturePolicy(harnessID: "opencode", status: status, selectedModel: "provider/vision")
        XCTAssertTrue(policy.supportsLocalImageInput)
        XCTAssertTrue(policy.supportsAppShots)
        XCTAssertTrue(policy.supportsReasoning)
        XCTAssertTrue(policy.supportsContextCompaction)
        XCTAssertFalse(policy.supportsGoalMode)
        XCTAssertFalse(policy.supportsSpeedMode)
        XCTAssertTrue(policy.supportsReadOnlyOneShotPrompts)
        XCTAssertTrue(policy.supportsIsolatedReviewWorkers)
        XCTAssertFalse(policy.supportsNativeBackgroundTasks)
        XCTAssertFalse(policy.supportsAdvancedSubagentControl)
        XCTAssertFalse(policy.supportsRawTranscriptLog)
    }

    func testOpenCodeFullAccessIsPresentedAsAWarning() {
        XCTAssertTrue(ChatComposerPermissionPresentation.isWarning(harnessID: "opencode", value: "fullAccess"))
        XCTAssertEqual(ChatComposerPermissionPresentation.symbolName(harnessID: "opencode", value: "fullAccess"), "exclamationmark.shield")
        XCTAssertFalse(ChatComposerPermissionPresentation.isWarning(harnessID: "opencode", value: "configured"))
        XCTAssertFalse(ChatComposerPermissionPresentation.isWarning(harnessID: "opencode", value: "ask"))
    }

    #if DEBUG
    func testOpenCodeDoesNotOpenAnUnsupportedRawJSONLViewer() {
        XCTAssertNil(RawTranscriptSource(harnessID: "opencode", harnessSessionID: "ses_test", workingDirectory: "/tmp/project"))
        XCTAssertNotNil(RawTranscriptSource(harnessID: "codex", harnessSessionID: "thread_test", workingDirectory: "/tmp/project"))
    }
    #endif
}
