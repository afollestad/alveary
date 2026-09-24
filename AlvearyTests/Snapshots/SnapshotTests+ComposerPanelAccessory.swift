@preconcurrency import AppKit
import XCTest

@testable import Alveary

// Fixture companion; the snapshot test itself stays in `SnapshotTests+ComposerPanel.swift` so its
// baseline lookup path is unchanged.
@MainActor
extension SnapshotTests {
    var exitPlanModeReasoningAccessory: AppKitComposerOverlayAccessory {
        let selection = ReasoningSelection(
            harnessID: "claude",
            harnessTitle: "Claude Code",
            modelID: "opus",
            modelTitle: "Opus",
            effortValue: "high",
            effortTitle: "High",
            effortOptions: [
                .init(value: "medium", title: "Medium"),
                .init(value: "high", title: "High")
            ],
            defaultEffortValue: "high",
            speedMode: .standard,
            supportsSpeedMode: false
        )
        return AppKitComposerOverlayAccessory(
            selection: selection,
            reasoning: ReasoningConfiguration(
                selection: selection,
                modelGroups: [
                    ReasoningModelGroup(
                        harnessID: "claude",
                        harnessTitle: nil,
                        options: [
                            .init(harnessID: "claude", value: "sonnet", title: "Sonnet"),
                            .init(harnessID: "claude", value: "opus", title: "Opus")
                        ]
                    )
                ],
                onEffortChange: { _ in true },
                onSpeedChange: { _ in true },
                onModelChange: { _ in .rejected }
            ),
            isEnabled: true
        )
    }
}
