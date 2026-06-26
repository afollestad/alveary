import ApplicationServices
@testable import Alveary
import XCTest

final class AppShotAXTreeFormatterTests: XCTestCase {
    func testStaticTextUsesCodexTextRoleAndDropsDuplicateDescription() {
        let line = AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXStaticTextRole as String,
            role: "text",
            inlineText: AppShotAXInlineText(text: "Dragon Princess 🐲🖤, Pinned", source: .staticText),
            value: AppShotAXValue(text: "Dragon Princess 🐲🖤, Pinned", typeName: "string"),
            description: "Dragon Princess 🐲🖤, Pinned"
        ))

        XCTAssertEqual(line, "text Dragon Princess 🐲🖤, Pinned")
    }

    func testTextAreaUsesCodexTextEntryAreaRoleAndValueDetails() {
        let line = AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXTextAreaRole as String,
            role: "text entry area",
            value: AppShotAXValue(text: "Hehehe yesss so cute", typeName: "string"),
            identifier: "CKBalloonTextView",
            settable: true
        ))

        XCTAssertEqual(line, "text entry area (settable, string) Value: Hehehe yesss so cute, ID: CKBalloonTextView")
    }

    func testPlainTextFieldUsesDescriptionHelpPlaceholderAndIdentifierDetails() {
        let line = AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXTextFieldRole as String,
            role: "text field",
            title: "Message",
            value: AppShotAXValue(text: nil, typeName: "string"),
            help: "Sylvie Circle",
            identifier: "messageBodyField",
            placeholder: "Text Message • RCS",
            settable: true
        ))

        XCTAssertEqual(line, "text field Description: Message, Help: Sylvie Circle, Placeholder: Text Message • RCS, ID: messageBodyField")
    }

    func testSearchTextFieldUsesInlineTextAndSettableValueType() {
        let line = AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXTextFieldRole as String,
            subrole: kAXSearchFieldSubrole as String,
            role: "search text field",
            inlineText: AppShotAXInlineText(text: "Search", source: .title),
            value: AppShotAXValue(text: nil, typeName: "string"),
            description: "Search",
            settable: true
        ))

        XCTAssertEqual(line, "search text field (settable, string) Search")
    }

    func testContainerDescriptionPromotionMatchesCodexShape() {
        let describedContainer = AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXGroupRole as String,
            role: "container",
            inlineText: AppShotAXInlineText(text: "Dad, Includes picture, 7:50 AM", source: .description),
            description: "Dad, Includes picture, 7:50 AM"
        ))
        let identifiedContainer = AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXGroupRole as String,
            role: "container",
            description: "Conversations",
            identifier: "ConversationList"
        ))

        XCTAssertEqual(describedContainer, "container Dad, Includes picture, 7:50 AM")
        XCTAssertEqual(identifiedContainer, "container Description: Conversations, ID: ConversationList")
    }

    func testBlankStaticTextIsSuppressed() {
        XCTAssertNil(AppShotAXTreeFormatter.renderedLine(for: presentation(
            rawRole: kAXStaticTextRole as String,
            role: "text"
        )))
    }

    func testTransparentWrapperOnlyPrunesSingleChildContainers() {
        let emptyContainer = presentation(rawRole: kAXGroupRole as String, role: "container")
        let idOnlySingleChildContainer = presentation(
            rawRole: kAXGroupRole as String,
            role: "container",
            identifier: "CKConversationListCollectionView"
        )
        let idOnlyMultiChildContainer = presentation(
            rawRole: kAXGroupRole as String,
            role: "container",
            inlineText: AppShotAXInlineText(text: "MessageEntryView", source: .identifier),
            identifier: "MessageEntryView"
        )

        XCTAssertFalse(emptyContainer.isTransparentWrapper(childCount: 4))
        XCTAssertTrue(emptyContainer.isTransparentWrapper(childCount: 1))
        XCTAssertTrue(idOnlySingleChildContainer.isTransparentWrapper(childCount: 1))
        XCTAssertFalse(idOnlyMultiChildContainer.isTransparentWrapper(childCount: 4))
    }
}

private func presentation(
    rawRole: String,
    subrole: String? = nil,
    role: String,
    inlineText: AppShotAXInlineText? = nil,
    title: String? = nil,
    value: AppShotAXValue? = nil,
    description: String? = nil,
    help: String? = nil,
    identifier: String? = nil,
    placeholder: String? = nil,
    selected: Bool = false,
    settable: Bool = false
) -> AppShotAXElementPresentation {
    AppShotAXElementPresentation(
        rawRole: rawRole,
        subrole: subrole,
        role: role,
        inlineText: inlineText,
        title: title,
        value: value,
        description: description,
        help: help,
        identifier: identifier,
        placeholder: placeholder,
        selected: selected,
        settable: settable
    )
}
