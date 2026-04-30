import SwiftUI

struct DiffImagePreviewScrollView: View {
    let preview: DiffImagePreview
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
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
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
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
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
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

private struct DiffImagePreviewSlot: View {
    let version: DiffImageVersion
    let loadImage: (DiffImageVersion) async throws -> DiffImagePreviewOutput
    let openImage: (DiffImageVersion) async throws -> Void

    @State private var state: DiffImagePreviewSlotState = .idle
    @State private var isOpening = false
    @State private var openingTask: Task<Void, Never>?

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
            state = .idle
            isOpening = false
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(version.side.rawValue.capitalized) image preview")
        .accessibilityAddTraits(state.isLoaded ? .isButton : [])
    }

    @ViewBuilder
    private var slotContent: some View {
        switch state {
        case .idle, .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let output):
            Image(decorative: output.image, scale: 1, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: .fit)
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

    private func load() async {
        state = .loading
        do {
            let output = try await loadImage(version)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(output)
        } catch is CancellationError {
            state = .idle
        } catch {
            guard !Task.isCancelled else {
                return
            }
            state = .failed
        }
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
    case loaded(DiffImagePreviewOutput)
    case failed

    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
}

private extension DiffImagePreviewSlot {
    var helpText: String {
        switch state {
        case .idle, .loading:
            return "Loading image preview"
        case .loaded:
            return "Open image in Preview"
        case .failed:
            return "Image preview unavailable"
        }
    }
}
