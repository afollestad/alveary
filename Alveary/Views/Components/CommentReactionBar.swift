import SwiftUI

/// One non-empty reaction group on a comment. `content` is the provider's raw
/// palette value; views only echo it back through the toggle callback.
struct CommentReaction: Hashable, Sendable {
    let content: String
    let emoji: String
    let count: Int
    let viewerHasReacted: Bool
}

/// A palette entry offered by the add-reaction picker.
struct CommentReactionOption: Hashable, Sendable {
    let content: String
    let emoji: String
}

/// Existing reaction chips plus the add-reaction picker, GitHub style: clicking a
/// chip toggles the viewer's reaction, the smiley opens the fixed emoji palette.
struct CommentReactionBar: View {
    let reactions: [CommentReaction]
    /// The palette; empty hides the add-reaction affordance.
    let options: [CommentReactionOption]
    let onToggle: (String) -> Void

    @State private var isPickerPresented = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(reactions, id: \.content) { reaction in
                CommentReactionChip(reaction: reaction) {
                    onToggle(reaction.content)
                }
                // The count is the only text; the emoji carries the meaning, so the
                // tooltip is the sighted reader's name for the control.
                .help(reactionAccessibilityLabel(for: reaction))
                .accessibilityLabel(reactionAccessibilityLabel(for: reaction))
            }

            if !options.isEmpty {
                CommentReactionAddButton {
                    isPickerPresented.toggle()
                }
                .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
                    reactionPicker
                }
            }
        }
        .padding(.top, 2)
    }

    private var reactionPicker: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.content) { option in
                Button {
                    isPickerPresented = false
                    onToggle(option.content)
                } label: {
                    Text(option.emoji)
                        .font(.system(size: 16))
                        .padding(5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(viewerReacted(option.content) ? Color.accentColor.opacity(0.18) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pickerAccessibilityLabel(for: option))
            }
        }
        .padding(8)
    }

    private func viewerReacted(_ content: String) -> Bool {
        reactions.first { $0.content == content }?.viewerHasReacted ?? false
    }

    private func reactionAccessibilityLabel(for reaction: CommentReaction) -> String {
        let state = reaction.viewerHasReacted ? "you reacted" : "you have not reacted"
        return "\(reaction.emoji), \(reaction.count), \(state)"
    }

    private func pickerAccessibilityLabel(for option: CommentReactionOption) -> String {
        viewerReacted(option.content) ? "Remove \(option.emoji) reaction" : "React with \(option.emoji)"
    }
}

/// One reaction group. Both chrome states already carry a fill, so hover deepens
/// the fill the chip already has rather than adding the icon buttons' circle —
/// this control has visible content, so it is not an icon-only button.
private struct CommentReactionChip: View {
    let reaction: CommentReaction
    let onToggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onToggle) {
            Text("\(reaction.emoji) \(reaction.count)")
                .font(.caption)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(fill))
                .overlay(
                    Capsule().strokeBorder(
                        reaction.viewerHasReacted ? Color.accentColor : .clear,
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var fill: Color {
        if reaction.viewerHasReacted {
            return Color.accentColor.opacity(isHovering ? 0.28 : 0.18)
        }

        return Color.secondary.opacity(isHovering ? 0.2 : 0.1)
    }
}

/// The add-reaction affordance. It keeps its resting circle and border — the
/// picker is otherwise undiscoverable — so hover deepens that fill instead of
/// taking `iconActionButtonStyle`, whose circle appears only on hover.
private struct CommentReactionAddButton: View {
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            Image(systemName: "face.smiling")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(4)
                .background(Circle().fill(Color.secondary.opacity(isHovering ? 0.22 : 0.1)))
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Add reaction")
        .accessibilityLabel("Add reaction")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
