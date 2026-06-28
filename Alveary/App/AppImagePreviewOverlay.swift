@preconcurrency import AppKit
import SwiftUI

struct AppImagePreviewOverlay: View {
    typealias ImageLoader = @MainActor (AppImagePreviewRequest) async throws -> AppImagePreviewLoadedImage
    typealias ImageSaver = @MainActor (AppImagePreviewRequest, AppImagePreviewLoadedImage) async throws -> Bool

    let request: AppImagePreviewRequest
    let onDismiss: () -> Void

    private let imageLoader: ImageLoader
    private let imageSaver: ImageSaver
    private let initialLoadedImage: AppImagePreviewLoadedImage?
    private let initialTextMode: Bool

    @State private var loadState: LoadState
    @State private var zoomCommand: AppImagePreviewZoomCommand?
    @State private var zoomState = AppImagePreviewZoomState.identity
    @State private var isViewingText = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var currentRequestID: UUID

    init(
        request: AppImagePreviewRequest,
        onDismiss: @escaping () -> Void,
        imageLoader: @escaping ImageLoader = { request in
            try await AppImagePreviewLoader().load(request)
        },
        imageSaver: @escaping ImageSaver = { request, loadedImage in
            try await AppImagePreviewSaver().save(request: request, loadedImage: loadedImage)
        },
        initialLoadedImage: AppImagePreviewLoadedImage? = nil,
        initialTextMode: Bool = false
    ) {
        self.request = request
        self.onDismiss = onDismiss
        self.imageLoader = imageLoader
        self.imageSaver = imageSaver
        self.initialLoadedImage = initialLoadedImage
        self.initialTextMode = initialTextMode
        _loadState = State(initialValue: initialLoadedImage.map(LoadState.loaded) ?? .loading)
        _isViewingText = State(initialValue: initialTextMode && request.textPayload != nil)
        _currentRequestID = State(initialValue: request.id)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.78)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                previewLayer(availableSize: proxy.size)
                topControlsContrastGradient
                    .frame(height: 168)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if showsBottomControlsContrastGradient {
                    bottomControlsContrastGradient
                        .frame(height: 132)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                topRightControls
                    .padding(.top, 14)
                    .padding(.trailing, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                footerControls
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .zIndex(1000)
        .onExitCommand(perform: onDismiss)
        .task(id: request.id) {
            await loadImage()
        }
    }

    @ViewBuilder
    private func previewLayer(availableSize: CGSize) -> some View {
        if case .loaded(let loaded) = loadState, !isViewingText {
            AppImagePreviewZoomView(
                image: loaded.image,
                command: zoomCommand,
                onZoomStateChanged: { zoomState = $0 },
                onBackgroundClick: { onDismiss() }
            )
            .frame(width: availableSize.width, height: availableSize.height)
            .background(Color.black.opacity(0.10))
            .contentShape(Rectangle())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(request.textPayload != nil ? "App shot preview" : "Image preview")
            .accessibilityValue(request.title)
        } else {
            framedViewport(availableSize: availableSize)
        }
    }

    private func framedViewport(availableSize: CGSize) -> some View {
        let size = AppImagePreviewLayout.viewportSize(for: availableSize)
        return viewport(size: size)
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var topControlsContrastGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.84), location: 0),
                .init(color: .black.opacity(0.70), location: 0.34),
                .init(color: .black.opacity(0.38), location: 0.66),
                .init(color: .black.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var bottomControlsContrastGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0.46), location: 0.58),
                .init(color: .black.opacity(0.70), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var showsBottomControlsContrastGradient: Bool {
        saveError != nil || (loadState.isLoaded && !isViewingText)
    }

    private func viewport(size: CGSize) -> some View {
        ZStack {
            content
        }
        .frame(width: size.width, height: size.height)
        .background(Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.32), radius: 28, x: 0, y: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.textPayload != nil ? "App shot preview" : "Image preview")
        .accessibilityValue(request.title)
    }

    @ViewBuilder
    private var topRightControls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                if request.textPayload != nil {
                    Button {
                        saveError = nil
                        isViewingText.toggle()
                    } label: {
                        Text(isViewingText ? "View image" : "View text")
                    }
                    .buttonStyle(PreviewTopTextButtonStyle())
                    .accessibilityLabel(isViewingText ? "View image" : "View text")
                    .accessibilityHint("Switches between the app shot image and captured accessibility tree.")
                }

                if loadState.loadedImage != nil {
                    Button {
                        saveLoadedImage()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "arrow.down")
                                .frame(width: 18, height: 18)
                        }
                    }
                    .buttonStyle(PreviewTopIconButtonStyle())
                    .disabled(isSaving)
                    .accessibilityLabel("Download image")
                    .accessibilityHint("Choose a location to save a copy of the image.")
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PreviewTopIconButtonStyle())
                .accessibilityLabel("Close image preview")
                .accessibilityHint("Closes the image preview.")
            }
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        if let saveError {
            Text(saveError)
                .font(.callout)
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.78), in: Capsule())
                .accessibilityLabel("Image save failed")
                .accessibilityValue(saveError)
        } else if loadState.isLoaded && !isViewingText {
            HStack(spacing: 4) {
                PreviewIconButton(systemName: "minus", accessibilityLabel: "Zoom out") {
                    zoomCommand = AppImagePreviewZoomCommand(action: .zoomOut)
                }
                .accessibilityHint("Zooms the preview image out.")

                Button(zoomPercentageText) {
                    zoomCommand = AppImagePreviewZoomCommand(action: .fit)
                }
                .buttonStyle(PreviewFooterTextButtonStyle())
                .accessibilityLabel("Reset zoom")
                .accessibilityValue(zoomPercentageText)
                .accessibilityHint("Resets the image zoom to the fitted 100 percent size.")

                PreviewIconButton(systemName: "plus", accessibilityLabel: "Zoom in") {
                    zoomCommand = AppImagePreviewZoomCommand(action: .zoomIn)
                }
                .accessibilityHint("Zooms the preview image in.")
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    @ViewBuilder
    private var content: some View {
        if isViewingText, let textPayload = request.textPayload {
            AppImagePreviewTextView(
                text: textPayload.text,
                accessibilityLabel: textPayload.title,
                onEscape: onDismiss
            )
        } else {
            switch loadState {
            case .loading:
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded:
                EmptyView()
            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                    Text("Image unavailable")
                        .font(.headline)
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                }
                .foregroundStyle(.white)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func loadImage() async {
        resetTransientStateForRequest()
        if let initialLoadedImage {
            loadState = .loaded(initialLoadedImage)
            zoomCommand = AppImagePreviewZoomCommand(action: .fit)
            return
        }
        loadState = .loading
        do {
            let loaded = try await imageLoader(request)
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

    private func resetTransientStateForRequest() {
        zoomCommand = nil
        zoomState = .identity
        saveError = nil
        isSaving = false
        isViewingText = initialTextMode && request.textPayload != nil
        currentRequestID = request.id
    }

    private func saveLoadedImage() {
        guard let loadedImage = loadState.loadedImage,
              !isSaving else {
            return
        }
        let savingRequest = request
        let savingRequestID = currentRequestID
        isSaving = true
        saveError = nil
        Task { @MainActor in
            do {
                _ = try await imageSaver(savingRequest, loadedImage)
                guard currentRequestID == savingRequestID else {
                    return
                }
                isSaving = false
            } catch {
                guard currentRequestID == savingRequestID else {
                    return
                }
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    private var zoomPercentageText: String {
        "\(Int((zoomState.displayScale * 100).rounded()))%"
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

        var loadedImage: AppImagePreviewLoadedImage? {
            guard case .loaded(let image) = self else {
                return nil
            }
            return image
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
        }
        .buttonStyle(PreviewFooterIconButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PreviewTopTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}

private struct PreviewTopIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.94))
            .tint(.white.opacity(0.94))
            .frame(width: 42, height: 42)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
    }
}

private struct PreviewFooterIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .frame(width: 34, height: 34)
            .contentShape(Rectangle())
    }
}

private struct PreviewFooterTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .frame(minWidth: 62, minHeight: 34)
            .contentShape(Rectangle())
    }
}

struct AppImagePreviewLayout {
    static func viewportSize(for availableSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(availableSize.width - 80, 320), 1_120),
            height: min(max(availableSize.height - 80, 260), 820)
        )
    }
}
