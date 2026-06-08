import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerReasoningMenuLayoutTests: XCTestCase {
    func testReasoningMenuHeaderSpacingAndTextAlignment() throws {
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                effortOptions: [
                    .init(value: "low", title: "Low"),
                    .init(value: "medium", title: "Medium")
                ]
            ),
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let header = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Reasoning"
            }
        )
        let firstRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Low"
            }
        )
        let divider = try XCTUnwrap(controller.view.descendants(of: AppKitComposerPopoverDividerView.self).first)
        let modelHeader = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Model"
            }
        )
        let modelRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Model"
            }
        )

        XCTAssertEqual(header.frame.minY, ComposerReasoningMenuMetrics.verticalInset, accuracy: 1)
        XCTAssertEqual(firstRow.frame.minY - header.frame.maxY, ComposerReasoningMenuMetrics.headerBottomSpacing, accuracy: 1)
        XCTAssertEqual(firstRow.frame.minX + ComposerReasoningMenuMetrics.titleLeading, header.frame.minX, accuracy: 1)
        XCTAssertEqual(modelHeader.frame.minY - divider.frame.maxY, ComposerReasoningMenuMetrics.dividerSpacing, accuracy: 1)
        XCTAssertEqual(modelRow.frame.minY - modelHeader.frame.maxY, ComposerReasoningMenuMetrics.headerBottomSpacing, accuracy: 1)
        XCTAssertEqual(modelHeader.frame.minX, header.frame.minX, accuracy: 1)
        XCTAssertEqual(modelRow.frame.minX + ComposerReasoningMenuMetrics.titleLeading, modelHeader.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(header.frame.height, header.fontLineHeight)
        assertHeaderTextBottomInset(header)
        assertHeaderTextBottomInset(modelHeader)
    }

    func testReasoningMenusUseSharedComposerPopoverSurface() throws {
        let mainController = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(),
            onRequestCloseMainMenu: {}
        )
        mainController.loadViewIfNeeded()
        XCTAssertTrue(mainController.view is AppKitComposerPopoverSurfaceView)
        XCTAssertFalse(mainController.view is NSVisualEffectView)
        XCTAssertNil(mainController.view.layer?.backgroundColor)

        let modelController = makeGroupedReasoningModelMenu()
        modelController.loadViewIfNeeded()
        XCTAssertTrue(modelController.view is AppKitComposerPopoverSurfaceView)
        XCTAssertFalse(modelController.view is NSVisualEffectView)
        XCTAssertNil(modelController.view.layer?.backgroundColor)

        let permissionController = ComposerPermissionMenuViewController(
            options: [
                .init(
                    value: "default",
                    title: "Default",
                    description: "Ask before file edits and restricted tool actions.",
                    symbolName: "hand.raised"
                )
            ],
            selectedValue: "default",
            onPermissionSelected: { _ in },
            onRequestCloseMainMenu: {}
        )
        permissionController.loadViewIfNeeded()
        XCTAssertTrue(permissionController.view is AppKitComposerPopoverSurfaceView)
        XCTAssertFalse(permissionController.view is NSVisualEffectView)
        XCTAssertNil(permissionController.view.layer?.backgroundColor)
    }

    func testReasoningButtonProgressKeepsCompactTextDropdownMetrics() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(makeConfiguration(mode: .idle))
        let idleButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)
        let idleSize = idleButton.intrinsicContentSize

        row.configure(makeConfiguration(mode: .progressOnly(.reconfiguringSession)))
        let progressButton = try XCTUnwrap(row.descendants(of: ComposerReasoningButton.self).first)

        XCTAssertEqual(progressButton.intrinsicContentSize, idleSize)
        #if DEBUG
        XCTAssertTrue(progressButton.debugShowsProgress)
        #endif
    }

    func testReasoningMenuRowsDoNotShowInteractionBackgroundForFirstResponderAlone() {
        let row = ComposerReasoningMenuRowView(frame: NSRect(x: 0, y: 0, width: 160, height: ComposerReasoningMenuMetrics.rowHeight))
        row.configure(.init(
            title: "Low",
            iconName: nil,
            trailingIconName: nil,
            accessibilityLabel: "Low",
            isSelected: false,
            isEnabled: true,
            action: {},
            hoverAction: nil,
            cancelAction: {}
        ))
        let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = row

        XCTAssertTrue(window.makeFirstResponder(row))
        #if DEBUG
        XCTAssertFalse(row.debugShowsInteractionBackground)
        #endif
    }

    func testReasoningMenuModelSelectionKeepsMainMenuOpen() {
        var closeCount = 0
        let modelOptions: [ChatComposerActionRowView.MenuOption] = [
            .init(value: "sonnet", title: "Sonnet"),
            .init(value: "opus", title: "Opus")
        ]
        let controller = ComposerReasoningMenuViewController(
            configuration: makeReasoningConfiguration(
                modelOptions: modelOptions,
                onModelChange: { request in
                    .applied(selection: makeReasoningConfiguration(
                        modelOptions: modelOptions,
                        selectedModel: request.modelID
                    ).selection)
                }
            ),
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()

        controller.selectModel(.init(providerID: "claude", modelID: "opus"))

        XCTAssertEqual(closeCount, 0)
        XCTAssertNotNil(controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
            $0.accessibilityLabel() == "Model"
        })
    }

    func testReasoningModelSubmenuHeaderAndDividerSpacing() throws {
        let controller = makeGroupedReasoningModelMenu()
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let claudeHeader = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Claude Code"
            }
        )
        let selectedRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Provider default"
            }
        )
        let divider = try XCTUnwrap(controller.view.descendants(of: AppKitComposerPopoverDividerView.self).first)
        let codexHeader = try XCTUnwrap(
            controller.view.descendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Codex"
            }
        )

        XCTAssertEqual(claudeHeader.frame.minY, ComposerReasoningMenuMetrics.verticalInset, accuracy: 1)
        XCTAssertEqual(selectedRow.frame.minY - claudeHeader.frame.maxY, ComposerReasoningMenuMetrics.headerBottomSpacing, accuracy: 1)
        XCTAssertEqual(selectedRow.frame.minX + ComposerReasoningMenuMetrics.titleLeading, claudeHeader.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(claudeHeader.frame.height, claudeHeader.fontLineHeight)
        assertHeaderTextBottomInset(claudeHeader)
        XCTAssertEqual(divider.frame.minY - selectedRow.frame.maxY, ComposerReasoningMenuMetrics.dividerSpacing, accuracy: 1)
        XCTAssertEqual(codexHeader.frame.minY - divider.frame.maxY, ComposerReasoningMenuMetrics.dividerSpacing, accuracy: 1)
        XCTAssertGreaterThan(codexHeader.frame.height, codexHeader.fontLineHeight)
        assertHeaderTextBottomInset(codexHeader)
    }

    func testSharedPopoverDividerResolvesAppearanceColor() throws {
        let divider = AppKitComposerPopoverDividerView(frame: NSRect(
            x: 0,
            y: 0,
            width: 160,
            height: AppKitComposerPopoverDividerView.height
        ))

        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
            divider.appearance = appearance
            divider.viewDidChangeEffectiveAppearance()

            let expected = NSColor.labelColor
                .resolved(for: appearance)
                .withAlphaComponent(AppKitComposerPopoverDividerView.alpha)
            assertColor(divider.layer?.backgroundColor, equals: expected)
        }
    }

    private func assertHeaderTextBottomInset(
        _ header: ComposerReasoningHeaderView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #if DEBUG
        XCTAssertEqual(
            header.debugTitleDrawingRect.maxY,
            header.bounds.height,
            accuracy: 1,
            file: file,
            line: line
        )
        #endif
    }

    private func assertColor(
        _ actualColor: CGColor?,
        equals expectedColor: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actualColor,
              let actual = NSColor(cgColor: actualColor)?.usingColorSpace(.deviceRGB),
              let expected = expectedColor.usingColorSpace(.deviceRGB) else {
            XCTFail("Expected comparable colors", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, expected.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, expected.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private extension NSTextField {
    var fontLineHeight: CGFloat {
        guard let font else {
            return 0
        }
        return ceil(font.ascender - font.descender + font.leading)
    }
}
