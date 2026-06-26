@preconcurrency import AppKit
import SwiftUI

struct AppImagePreviewOverlay: View {
    let request: AppImagePreviewRequest
    let onDismiss: () -> Void

    @State private var loadState = LoadState.loading
    @State private var zoomCommand: AppImagePreviewZoomCommand?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.54)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                panel(availableSize: proxy.size)
            }
        }
        .zIndex(1000)
        .background(AppImagePreviewEscapeKeyCatcher(onEscape: onDismiss).frame(width: 0, height: 0))
        .focusable()
        .onExitCommand(perform: onDismiss)
        .task(id: request.id) {
            await loadImage()
        }
    }

    private func panel(availableSize: CGSize) -> some View {
        let width = min(max(availableSize.width - 80, 320), 1_120)
        let height = min(max(availableSize.height - 80, 260), 820)
        return VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: width, height: height)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 18)
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(request.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            PreviewIconButton(systemName: "arrow.down.right.and.arrow.up.left", accessibilityLabel: "Fit image") {
                zoomCommand = AppImagePreviewZoomCommand(action: .fit)
            }
            .disabled(!loadState.isLoaded)

            PreviewIconButton(systemName: "1.magnifyingglass", accessibilityLabel: "Actual size") {
                zoomCommand = AppImagePreviewZoomCommand(action: .actualSize)
            }
            .disabled(!loadState.isLoaded)

            PreviewIconButton(systemName: "minus.magnifyingglass", accessibilityLabel: "Zoom out") {
                zoomCommand = AppImagePreviewZoomCommand(action: .zoomOut)
            }
            .disabled(!loadState.isLoaded)

            PreviewIconButton(systemName: "plus.magnifyingglass", accessibilityLabel: "Zoom in") {
                zoomCommand = AppImagePreviewZoomCommand(action: .zoomIn)
            }
            .disabled(!loadState.isLoaded)

            PreviewIconButton(systemName: "xmark", accessibilityLabel: "Close image preview", action: onDismiss)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let loaded):
            AppImagePreviewZoomView(image: loaded.image, command: zoomCommand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.06))
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Image unavailable")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadImage() async {
        loadState = .loading
        do {
            let loaded = try await AppImagePreviewLoader().load(request)
            guard !Task.isCancelled else {
                return
            }
            loadState = .loaded(loaded)
            zoomCommand = AppImagePreviewZoomCommand(action: .fit)
        } catch {
            guard !Task.isCancelled else {
                return
            }
            loadState = .failed(error.localizedDescription)
        }
    }

    private enum LoadState {
        case loading
        case loaded(AppImagePreviewLoadedImage)
        case failed(String)

        var isLoaded: Bool {
            if case .loaded = self {
                return true
            }
            return false
        }
    }
}

private struct PreviewIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct AppImagePreviewEscapeKeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeKeyCatcherView {
        let view = EscapeKeyCatcherView()
        view.onEscape = onEscape
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: EscapeKeyCatcherView, context: Context) {
        nsView.onEscape = onEscape
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

@MainActor
private final class EscapeKeyCatcherView: NSView {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
