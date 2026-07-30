import AppKit
import SwiftUI

struct PullRequestAvatarView: View {
    let login: String
    let url: URL?
    let loader: GitHubAvatarLoader
    var diameter: CGFloat = 16

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                // Avatars can be dark glyphs on transparency (bot logos); a subtle
                // adaptive fill keeps them legible on both themes — GitHub uses
                // white at 10% in dark mode, and this is the same token the letter
                // placeholder already uses.
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                Text(String(login.prefix(1)).uppercased())
                    .font(.system(size: diameter * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            image = await loader.image(for: url)
        }
        // The adjacent author label carries the name; the avatar is decorative.
        .accessibilityHidden(true)
    }
}
