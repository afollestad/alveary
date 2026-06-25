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
        return line(for: presentation)
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

        let indent = String(repeating: " ", count: depth)
        var lines = [indent + line(for: presentation(for: element))]
        guard let children = children(for: element), !children.isEmpty else {
            return lines.joined(separator: "\n")
        }
        for child in children {
            guard let rendered = renderElement(
                child,
                depth: depth + 1,
                visited: &visited,
                renderedCount: &renderedCount
            ) else {
                continue
            }
            lines.append(rendered)
        }
        return lines.joined(separator: "\n")
    }

    private static func presentation(for element: AXUIElement) -> AXElementPresentation {
        let role = (copyAttribute(kAXRoleAttribute, from: element) as String?) ?? "AXUnknown"
        let subrole = copyAttribute(kAXSubroleAttribute, from: element) as String?
        let title = normalizedText(copyAttribute(kAXTitleAttribute, from: element) as String?)
        let value = normalizedValue(copyAttribute(kAXValueAttribute, from: element))
        let description = normalizedText(copyAttribute(kAXDescriptionAttribute, from: element) as String?)
        let help = normalizedText(copyAttribute(kAXHelpAttribute, from: element) as String?)
        let identifier = normalizedText(copyAttribute(kAXIdentifierAttribute, from: element) as String?)
        let selected = (copyAttribute(kAXSelectedAttribute, from: element) as Bool?) == true
        let settable = isValueSettable(element)

        return AXElementPresentation(
            role: displayRole(role: role, subrole: subrole),
            title: preferredTitle(role: role, title: title, value: value, description: description),
            value: valueForDetails(role: role, title: title, value: value),
            description: descriptionForDetails(role: role, title: title, description: description),
            help: help,
            identifier: identifier,
            selected: selected,
            settable: settable
        )
    }

    private static func line(for presentation: AXElementPresentation) -> String {
        var head = presentation.role
        if presentation.selected {
            head += " (selected)"
        }
        if let title = presentation.title {
            head += " \(title)"
        }

        var details: [String] = []
        if presentation.settable {
            details.append("settable")
        }
        if let description = presentation.description {
            details.append("Description: \(description)")
        }
        if let value = presentation.value {
            details.append("Value: \(value)")
        }
        if let help = presentation.help {
            details.append("Help: \(help)")
        }
        if let identifier = presentation.identifier {
            details.append("ID: \(identifier)")
        }
        guard !details.isEmpty else {
            return head
        }
        return head + ", " + details.joined(separator: ", ")
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
        let roleName = role.removingAXPrefix
        return roleName.splitCamelCase.lowercased()
    }

    private static func preferredTitle(role: String, title: String?, value: String?, description: String?) -> String? {
        if role == kAXStaticTextRole as String || role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
            return title ?? value ?? description
        }
        return title
    }

    private static func valueForDetails(role: String, title: String?, value: String?) -> String? {
        guard role != kAXStaticTextRole as String,
              role != kAXTextAreaRole as String,
              role != kAXTextFieldRole as String,
              value != title else {
            return nil
        }
        return value
    }

    private static func descriptionForDetails(role: String, title: String?, description: String?) -> String? {
        guard description != title else {
            return nil
        }
        if role == kAXStaticTextRole as String, title != nil {
            return nil
        }
        return description
    }

    private static func normalizedValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return normalizedText(string)
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }
}

private struct AXElementPresentation {
    let role: String
    let title: String?
    let value: String?
    let description: String?
    let help: String?
    let identifier: String?
    let selected: Bool
    let settable: Bool
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
