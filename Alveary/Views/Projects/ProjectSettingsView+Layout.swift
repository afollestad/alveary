import SwiftUI

/// Project editors use a denser grid than app-wide settings without changing their shared control chrome.
enum ProjectSettingsLayout {
    static let compactBreakpoint: CGFloat = 640
    static let rowSpacing: CGFloat = 8
    static let fieldVerticalPadding: CGFloat = 6
    static let sectionSpacing: CGFloat = 16
    static let sectionPadding: CGFloat = 14
}

struct ProjectSettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ProjectSettingsLayout.sectionSpacing) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(ProjectSettingsLayout.sectionPadding)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        }
    }
}
