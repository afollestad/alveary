import ApplicationServices
import Foundation

struct AppShotAXTreeSnapshot: Equatable, Sendable {
    let treeText: String
    let focusedElementSummary: String
}

enum AppShotAXTreeFormatter {
    private static let maxDepth = 10
    private static let maxNodes = 500

    static func snapshot(for target: AppShotWindowTarget) throws -> AppShotAXTreeSnapshot {
        guard AppShotPermission.accessibility.isAllowed else {
            throw AppShotCaptureError.accessibilityPermissionMissing
        }

        var visited = Set<CFHashCode>()
        var renderedCount = 0
        let treeText = renderElement(
            target.axWindow,
            depth: 0,
            visited: &visited,
            renderedCount: &renderedCount
        ) ?? elementSummary(target.axWindow)

        let focusedElement = focusedElement(processIdentifier: target.processIdentifier) ?? target.axWindow
        return AppShotAXTreeSnapshot(
            treeText: treeText,
            focusedElementSummary: elementSummary(focusedElement)
        )
    }

    static func elementSummary(_ element: AXUIElement) -> String {
        let presentation = presentation(for: element)
        return renderedLine(for: presentation) ?? presentation.role
    }

    private static func renderElement(
        _ element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>,
        renderedCount: inout Int
    ) -> String? {
        guard depth <= maxDepth, renderedCount < maxNodes else {
            return nil
        }
        let hash = CFHash(element)
        guard visited.insert(hash).inserted else {
            return nil
        }
        renderedCount += 1

        let presentation = presentation(for: element)
        let children = children(for: element) ?? []
        let isTransparentWrapper = presentation.isTransparentWrapper(childCount: children.count)
        let childDepth = isTransparentWrapper ? depth : depth + 1
        var childLines: [String] = []
        for child in children {
            guard let rendered = renderElement(
                child,
                depth: childDepth,
                visited: &visited,
                renderedCount: &renderedCount
            ) else {
                continue
            }
            childLines.append(rendered)
        }

        guard !isTransparentWrapper, let currentLine = renderedLine(for: presentation) else {
            return childLines.isEmpty ? nil : childLines.joined(separator: "\n")
        }
        let indent = String(repeating: "\t", count: depth)
        var lines = [indent + currentLine]
        lines.append(contentsOf: childLines)
        return lines.joined(separator: "\n")
    }

    private static func presentation(for element: AXUIElement) -> AppShotAXElementPresentation {
        let role = (copyAttribute(kAXRoleAttribute, from: element) as String?) ?? "AXUnknown"
        let subrole = copyAttribute(kAXSubroleAttribute, from: element) as String?
        let title = normalizedText(copyAttribute(kAXTitleAttribute, from: element) as String?)
        let value = normalizedValue(copyAttribute(kAXValueAttribute, from: element))
        let description = normalizedText(copyAttribute(kAXDescriptionAttribute, from: element) as String?)
        let help = normalizedText(copyAttribute(kAXHelpAttribute, from: element) as String?)
        let identifier = normalizedText(copyAttribute(kAXIdentifierAttribute, from: element) as String?)
        let placeholder = normalizedText(copyAttribute(kAXPlaceholderValueAttribute, from: element) as String?)
        let selected = (copyAttribute(kAXSelectedAttribute, from: element) as Bool?) == true
        let settable = isValueSettable(element)

        return AppShotAXElementPresentation(
            rawRole: role,
            subrole: subrole,
            role: displayRole(role: role, subrole: subrole),
            inlineText: inlineText(for: AppShotAXRawAttributes(
                role: role,
                subrole: subrole,
                title: title,
                value: value?.text,
                description: description,
                identifier: identifier,
                placeholder: placeholder
            )),
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

    static func renderedLine(for presentation: AppShotAXElementPresentation) -> String? {
        if shouldSuppressLine(for: presentation) {
            return nil
        }

        var head = presentation.role
        if let valueMarker = valueMarker(for: presentation) {
            head += " (\(valueMarker))"
        }
        if presentation.selected {
            head += " (selected)"
        }
        if let inlineText = presentation.inlineText?.text {
            head += " \(inlineText)"
        }

        var details: [String] = []
        if let description = descriptionForDetails(presentation) {
            details.append("Description: \(description)")
        }
        if let value = valueForDetails(presentation) {
            details.append("Value: \(value)")
        }
        if let help = presentation.help {
            details.append("Help: \(help)")
        }
        if let placeholder = presentation.placeholder {
            details.append("Placeholder: \(placeholder)")
        }
        if let identifier = identifierForDetails(presentation) {
            details.append("ID: \(identifier)")
        }
        guard !details.isEmpty else {
            return head
        }
        let detailsPrefix = presentation.inlineText == nil ? " " : ", "
        return head + detailsPrefix + details.joined(separator: ", ")
    }

    private static func children(for element: AXUIElement) -> [AXUIElement]? {
        if let visibleChildren = copyAttribute(kAXVisibleChildrenAttribute, from: element) as [AXUIElement]?,
           !visibleChildren.isEmpty {
            return visibleChildren
        }
        return copyAttribute(kAXChildrenAttribute, from: element) as [AXUIElement]?
    }

    private static func focusedElement(processIdentifier: pid_t) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        return copyAttribute(kAXFocusedUIElementAttribute, from: applicationElement) as AXUIElement?
            ?? copyAttribute(kAXFocusedWindowAttribute, from: applicationElement) as AXUIElement?
    }

    private static func copyAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        AppShotTargetTracker.copyAttribute(attribute, from: element)
    }

    private static func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        return error == .success && settable.boolValue
    }

    private static func displayRole(role: String, subrole: String?) -> String {
        if role == kAXWindowRole as String, subrole == kAXStandardWindowSubrole as String {
            return "standard window"
        }
        if role == kAXGroupRole as String {
            return "container"
        }
        if role == kAXStaticTextRole as String {
            return "text"
        }
        if role == kAXTextAreaRole as String {
            return "text entry area"
        }
        if role == kAXTextFieldRole as String, subrole == kAXSearchFieldSubrole as String {
            return "search text field"
        }
        let roleName = role.removingAXPrefix
        return roleName.splitCamelCase.lowercased()
    }

    private static func shouldSuppressLine(for presentation: AppShotAXElementPresentation) -> Bool {
        if presentation.rawRole == kAXStaticTextRole as String, presentation.inlineText == nil {
            return true
        }
        return false
    }

    private static func inlineText(for attributes: AppShotAXRawAttributes) -> AppShotAXInlineText? {
        if attributes.role == kAXStaticTextRole as String {
            return inlineText(attributes.title ?? attributes.value ?? attributes.description, source: .staticText)
        }
        if attributes.role == kAXTextAreaRole as String {
            return nil
        }
        if attributes.role == kAXTextFieldRole as String {
            guard attributes.subrole == kAXSearchFieldSubrole as String else {
                return nil
            }
            return inlineText(attributes.title ?? attributes.value ?? attributes.description ?? attributes.placeholder, source: .title)
        }
        if attributes.role == kAXGroupRole as String {
            if let title = attributes.title {
                return inlineText(title, source: .title)
            }
            if attributes.identifier == nil, let description = attributes.description {
                return inlineText(description, source: .description)
            }
            if attributes.description == nil, let identifier = attributes.identifier {
                return inlineText(identifier, source: .identifier)
            }
            return nil
        }
        if attributes.role == kAXWindowRole as String {
            return inlineText(attributes.title, source: .title)
        }
        return inlineText(attributes.title, source: .title)
    }

    private static func inlineText(_ text: String?, source: AppShotAXInlineText.Source) -> AppShotAXInlineText? {
        guard let text else {
            return nil
        }
        return AppShotAXInlineText(text: text, source: source)
    }

    private static func valueMarker(for presentation: AppShotAXElementPresentation) -> String? {
        guard presentation.settable, shouldShowSettableMarker(for: presentation) else {
            return nil
        }
        guard let valueType = presentation.value?.typeName else {
            return "settable"
        }
        return "settable, \(valueType)"
    }

    private static func shouldShowSettableMarker(for presentation: AppShotAXElementPresentation) -> Bool {
        if presentation.rawRole == kAXTextFieldRole as String,
           presentation.subrole != kAXSearchFieldSubrole as String,
           presentation.value?.text == nil {
            return false
        }
        return true
    }

    private static func descriptionForDetails(_ presentation: AppShotAXElementPresentation) -> String? {
        guard let description = presentation.description else {
            if presentation.rawRole == kAXTextFieldRole as String {
                let title = presentation.title ?? ""
                return title.isEmpty ? nil : title
            }
            return nil
        }
        if presentation.rawRole == kAXButtonRole as String || presentation.role == "menu button" {
            return nil
        }
        if presentation.inlineText?.source == .description || presentation.inlineText?.text == description {
            return nil
        }
        if presentation.rawRole == kAXStaticTextRole as String || description == presentation.value?.text || description == presentation.title {
            return nil
        }
        return description
    }

    private static func valueForDetails(_ presentation: AppShotAXElementPresentation) -> String? {
        guard let value = presentation.value?.text,
              presentation.rawRole != kAXStaticTextRole as String,
              presentation.inlineText?.text != value else {
            return nil
        }
        return value
    }

    private static func identifierForDetails(_ presentation: AppShotAXElementPresentation) -> String? {
        guard presentation.inlineText?.source != .identifier else {
            return nil
        }
        return presentation.identifier
    }

    private static func normalizedValue(_ value: Any?) -> AppShotAXValue? {
        switch value {
        case let string as String:
            return AppShotAXValue(text: normalizedText(string), typeName: "string")
        case let number as NSNumber:
            return AppShotAXValue(text: number.stringValue, typeName: "float")
        default:
            return nil
        }
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct AppShotAXElementPresentation {
    let rawRole: String
    let subrole: String?
    let role: String
    let inlineText: AppShotAXInlineText?
    let title: String?
    let value: AppShotAXValue?
    let description: String?
    let help: String?
    let identifier: String?
    let placeholder: String?
    let selected: Bool
    let settable: Bool

    func isTransparentWrapper(childCount: Int) -> Bool {
        guard role == "container",
              inlineText == nil,
              description == nil,
              value?.text == nil,
              help == nil,
              placeholder == nil else {
            return false
        }
        return childCount <= 1
    }
}

struct AppShotAXInlineText: Equatable {
    let text: String
    let source: Source

    enum Source: Equatable {
        case title
        case staticText
        case description
        case identifier
    }
}

struct AppShotAXValue: Equatable {
    let text: String?
    let typeName: String
}

private struct AppShotAXRawAttributes {
    let role: String
    let subrole: String?
    let title: String?
    let value: String?
    let description: String?
    let identifier: String?
    let placeholder: String?
}

private extension String {
    var removingAXPrefix: String {
        hasPrefix("AX") ? String(dropFirst(2)) : self
    }

    var splitCamelCase: String {
        unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result.append(" ")
            }
            result.append(String(scalar))
        }
    }
}
