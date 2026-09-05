import SwiftUI

struct DiffImagePreviewScrollView: View {
    let preview: DiffImagePreview
    let loadImage: (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void

    var body: some View {
        DiffPreviewScrollContainer {
            GeometryReader { proxy in
                DiffImagePreviewSlots(
                    preview: preview,
                    loadImage: loadImage,
                    openImage: openImage
                )
                .frame(
                    width: max(proxy.size.width, 280),
                    height: max(proxy.size.height, 280)
                )
            }
            .frame(minHeight: 280)
        }
    }
}

struct DiffImagePreviewSlots: View {
    let preview: DiffImagePreview
    let loadImage: (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void

    var body: some View {
        HStack(spacing: preview.isSplit ? 8 : 0) {
            if let old = preview.old {
                DiffImagePreviewColumn(
                    version: old,
                    showsHeader: preview.isSplit,
                    loadImage: loadImage,
                    openImage: openImage
                )
            }

            if let new = preview.new {
                DiffImagePreviewColumn(
                    version: new,
                    showsHeader: preview.isSplit,
                    loadImage: loadImage,
                    openImage: openImage
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DiffImagePreviewColumn: View {
    let version: DiffImageVersion
    let showsHeader: Bool
    let loadImage: (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void

    var body: some View {
        VStack(spacing: showsHeader ? 6 : 0) {
            if showsHeader {
                Text(headerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(headerColor)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
            }

            DiffImagePreviewSlot(
                version: version,
                loadImage: loadImage,
                openImage: openImage
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerTitle: String {
        switch version.side {
        case .old:
            return "Deleted"
        case .new:
            return "Added"
        }
    }

    private var headerColor: Color {
        switch version.side {
        case .old:
            return .red
        case .new:
            return .green
        }
    }
}

/// Loads on visibility and drops everything on recycle: `onDisappear` cancels
/// in-flight open work and resets `state` to `.idle`, releasing the strong
/// decoded image so a scrolled-away slot cannot pin one. Reloads come back from
/// the memory/disk cache, so the release costs nothing visible.
private struct DiffImagePreviewSlot: View {
    let version: DiffImageVersion
    let loadImage: (DiffImageVersion, DiffImageLoadIntent) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void

    @State private var state: DiffImagePreviewSlotState = .idle
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?
    @State private var loadingTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            slotContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isOpening {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("Opening image")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .help(helpText)
        .onTapGesture {
            open()
        }
        .task(id: version) {
            await load()
        }
        .onDisappear {
            openingTask?.cancel()
            openingTask = nil
            loadingTask?.cancel()
            loadingTask = nil
            state = .idle
            isOpening = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(state.isActionable ? .isButton : [])
        // The slot flattens its children, so the confirmation card's button has no element of its
        // own — without this action a gated image could be seen but never loaded by VoiceOver.
        .accessibilityAction { activate() }
    }

    /// The slot's single activation, matching whatever its current state offers.
    private func activate() {
        switch state {
        case .needsConfirmation:
            load(intent: .confirmed)
        case .loaded:
            open()
        case .idle, .loading, .tooLarge, .failed:
            break
        }
    }

    @ViewBuilder
    private var slotContent: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsConfirmation(let byteSize):
            DiffImagePreviewConfirmationCard(byteSize: byteSize) {
                load(intent: .confirmed)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .tooLarge(let byteSize):
            DiffCalloutCard(
                icon: "exclamationmark.triangle",
                title: "Image too large",
                message: DiffImagePreviewByteFormat.tooLargeMessage(byteSize: byteSize)
            )
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let output):
            Image(decorative: output.image, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            DiffCalloutCard(
                icon: "doc.fill",
                title: "Binary diff",
                message: "Binary file changes cannot be rendered inline yet."
            )
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Runs the automatic load a freshly visible slot starts with. A size-gated image comes back as
    /// `.needsConfirmation` rather than a failure, because nothing is wrong with it — it is just
    /// bigger than we will pull down unasked.
    private func load() async {
        await performLoad(intent: .automatic)
    }

    /// The explicit re-run behind the confirmation card's button. Held in `loadingTask` so a recycle
    /// cancels it; `.task(id:)` only owns the automatic one.
    private func load(intent: DiffImageLoadIntent) {
        guard loadingTask == nil else {
            return
        }
        loadingTask = Task {
            await performLoad(intent: intent)
            loadingTask = nil
        }
    }

    private func performLoad(intent: DiffImageLoadIntent) async {
        state = .loading
        do {
            let output = try await loadImage(version, intent)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(output)
        } catch is CancellationError {
            state = .idle
        } catch let error as DiffImageBlobTooLargeError {
            guard !Task.isCancelled else {
                return
            }
            state = Self.gatedState(byteSize: error.byteSize ?? version.byteSize, version: version, intent: intent)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed
        }
    }

    /// Confirming can only help while the image is still under the hard cap, and never after a
    /// confirmed attempt has already been refused.
    private static func gatedState(
        byteSize: Int?,
        version: DiffImageVersion,
        intent: DiffImageLoadIntent
    ) -> DiffImagePreviewSlotState {
        if intent == .confirmed {
            return .tooLarge(byteSize)
        }
        if let byteSize,
           DiffImagePreviewSupport.exceedsHardLimit(byteSize: byteSize, source: version.source) {
            return .tooLarge(byteSize)
        }
        return .needsConfirmation(byteSize)
    }

    private func open() {
        guard openingTask == nil,
              case .loaded = state else {
            return
        }

        isOpening = true
        openingTask = Task {
            do {
                try await openImage(version)
            } catch is CancellationError {
                // The slot was recycled while temp materialization was still in flight.
            } catch {
                state = .failed
            }
            openingTask = nil
            isOpening = false
        }
    }
}

private enum DiffImagePreviewSlotState {
    case idle
    case loading
    /// Held back by the auto-load gate. Carries the size when it is known so the card can name it.
    case needsConfirmation(Int?)
    /// Past the hard cap, where confirming would not help.
    case tooLarge(Int?)
    case loaded(DiffImagePreviewOutput)
    case failed

    /// Whether activating the slot does anything — a gated image is as actionable as a loaded one.
    var isActionable: Bool {
        switch self {
        case .loaded, .needsConfirmation:
            return true
        case .idle, .loading, .tooLarge, .failed:
            return false
        }
    }
}

private extension DiffImagePreviewSlot {
    var accessibilityLabel: String {
        let side = version.side.rawValue.capitalized
        switch state {
        case .idle, .loading:
            return "\(side) image preview, loading"
        case .needsConfirmation(let byteSize):
            return "\(side) image preview, \(DiffImagePreviewByteFormat.largeImageTitle(byteSize: byteSize))"
        case .tooLarge:
            return "\(side) image preview, too large to preview"
        case .loaded:
            return "\(side) image preview, open"
        case .failed:
            return "\(side) image preview, unavailable"
        }
    }

    var helpText: String {
        switch state {
        case .idle, .loading:
            return "Loading image preview"
        case .needsConfirmation:
            return "Load this image"
        case .tooLarge:
            return "Image too large to preview"
        case .loaded:
            return "Open image"
        case .failed:
            return "Image preview unavailable"
        }
    }
}

/// Offers a size-gated image rather than downloading it on scroll. Git LFS holds large files by
/// design, so a pull request full of them would otherwise pull tens of megabytes unasked.
private struct DiffImagePreviewConfirmationCard: View {
    let byteSize: Int?
    let load: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(DiffImagePreviewByteFormat.largeImageTitle(byteSize: byteSize))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)

            Button("Load image", action: load)
                .secondaryActionButtonStyle()
                .accessibilityLabel("Load image")
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private enum DiffImagePreviewByteFormat {
    static func string(byteSize: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    static func largeImageTitle(byteSize: Int?) -> String {
        guard let byteSize else {
            return "Large image"
        }
        return "Large image \u{00B7} \(string(byteSize: byteSize))"
    }

    static func tooLargeMessage(byteSize: Int?) -> String {
        guard let byteSize else {
            return "This image is too large to preview inline."
        }
        return "This image is \(string(byteSize: byteSize)), past the inline preview limit."
    }
}
