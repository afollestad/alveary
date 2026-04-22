import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testShouldSubmitExactSkillAutocompleteReturnsTrueForExactSlashCommandMatch() {
        let autocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .skill,
            replacementOffsets: 0..<17,
            query: "review-github-pr",
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: "review-github-pr",
                    title: "review-github-pr",
                    subtitle: "Review a GitHub pull request",
                    trailingText: nil,
                    replacementText: "/review-github-pr",
                    symbolName: "shippingbox"
                )
            ],
            isLoading: false
        )

        XCTAssertTrue(
            ChatInputField.shouldSubmitExactSkillAutocomplete(
                text: "/review-github-pr",
                autocomplete: autocomplete
            )
        )
    }

    func testShouldSubmitExactSkillAutocompleteReturnsFalseForPartialSlashCommandMatch() {
        let autocomplete = ComposerAutocompleteState(
            sessionID: UUID(),
            kind: .skill,
            replacementOffsets: 0..<5,
            query: "revi",
            suggestions: [
                ComposerAutocompleteSuggestion(
                    id: "review-github-pr",
                    title: "review-github-pr",
                    subtitle: "Review a GitHub pull request",
                    trailingText: nil,
                    replacementText: "/review-github-pr",
                    symbolName: "shippingbox"
                )
            ],
            isLoading: false
        )

        XCTAssertFalse(
            ChatInputField.shouldSubmitExactSkillAutocomplete(
                text: "/revi",
                autocomplete: autocomplete
            )
        )
    }
}
