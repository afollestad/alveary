import AppKit
import SwiftUI

/// A comment author's avatar, or their initial while one is loading or absent.
///
/// Both states draw the same subtle circle behind them: a fetched avatar can be a dark
/// glyph on transparency (bot logos), so without a fill it disappears into a dark theme.
/// Decorative on purpose — the adjacent author label is what carries the name.
struct PullRequestAvatarView: View {
    let login: String
    let url: URL?
    let loader: GitHubAvatarLoader
    var diameter: CGFloat = 16

    /// Only ever holds an avatar *this* view had to fetch. A warm one is read straight off the
    /// loader below, so a row scrolling back into a `LazyVStack` costs no suspension and shows no
    /// placeholder frame; the state exists solely to redraw the row that paid for a cold load.
    @State private var fetchedImage: NSImage?

    var body: some View {
        // The loader is not observable, so this is a plain read that registers no dependency —
        // deliberately: a list re-rendering on every unrelated avatar landing is the cost the
        // synchronous cache exists to avoid.
        let image = url.flatMap { loader.cachedImage(for: $0) } ?? fetchedImage
        ZStack {
            // Avatars can be dark glyphs on transparency (bot logos); a subtle
            // adaptive fill keeps them legible on both themes — GitHub uses
            // white at 10% in dark mode, and this is the same token the letter
            // placeholder already uses.
            Circle()
                .fill(Color.secondary.opacity(0.2))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(String(login.prefix(1)).uppercased())
                    .font(.system(size: diameter * 0.55, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .task(id: url) {
            guard let url else {
                // A URL that became nil must drop what the old URL fetched, or the fallback
                // read above keeps showing the stale avatar under the letter placeholder's turn.
                fetchedImage = nil
                return
            }
            // Returns before suspending when the cache is already warm, which is the common case
            // once the list has been scrolled once. Kept as an unconditional modifier rather than
            // a conditional one: branching here would change the view's identity as the image
            // lands and discard the `@State` holding it.
            guard loader.cachedImage(for: url) == nil else {
                return
            }
            fetchedImage = await loader.image(for: url)
        }
        // The adjacent author label carries the name; the avatar is decorative.
        .accessibilityHidden(true)
    }
}
