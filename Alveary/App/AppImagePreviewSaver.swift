@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

struct AppImagePreviewSaveDestinationRequest: Equatable {
    let suggestedFileName: String
    let allowedContentTypes: [UTType]?
}

@MainActor
struct AppImagePreviewSaver {
    typealias DestinationPicker = @MainActor (AppImagePreviewSaveDestinationRequest) async -> URL?

    var destinationPicker: DestinationPicker
    var fileManager: FileManager

    init(
        destinationPicker: @escaping DestinationPicker = { request in
            await AppImagePreviewSavePanelPicker().destination(for: request)
        },
        fileManager: FileManager = .default
    ) {
        self.destinationPicker = destinationPicker
        self.fileManager = fileManager
    }

    @discardableResult
    func save(request: AppImagePreviewRequest, loadedImage: AppImagePreviewLoadedImage) async throws -> Bool {
        let localSource = readableLocalSource(for: request)
        let destinationRequest = Self.destinationRequest(for: request, localSource: localSource)
        guard let destinationURL = await destinationPicker(destinationRequest) else {
            return false
        }
        let standardizedDestination = destinationURL.standardizedFileURL
        if let localSource,
           localSource.standardizedFileURL == standardizedDestination {
            return true
        }
        if fileManager.fileExists(atPath: standardizedDestination.path) {
            try fileManager.removeItem(at: standardizedDestination)
        }
        if let localSource {
            try fileManager.copyItem(at: localSource, to: standardizedDestination)
        } else {
            try loadedImage.pngData().write(to: standardizedDestination, options: [.atomic])
        }
        return true
    }

    static func destinationRequest(
        for request: AppImagePreviewRequest,
        localSource: URL? = nil
    ) -> AppImagePreviewSaveDestinationRequest {
        if let localSource {
            return AppImagePreviewSaveDestinationRequest(
                suggestedFileName: sanitizedFileName(localSource.lastPathComponent, fallbackExtension: localSource.pathExtension),
                allowedContentTypes: allowedContentTypes(forOriginalExtension: localSource.pathExtension)
            )
        }
        return AppImagePreviewSaveDestinationRequest(
            suggestedFileName: sanitizedFileName(
                request.title,
                fallbackExtension: "png",
                replacesExistingExtension: true
            ),
            allowedContentTypes: [.png]
        )
    }

    static func sanitizedFileName(
        _ rawValue: String,
        fallbackExtension: String,
        replacesExistingExtension: Bool = false
    ) -> String {
        var name = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: "-")
        if name.isEmpty {
            name = "Image"
        }
        let fallbackExtension = fallbackExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallbackExtension.isEmpty else {
            return name
        }
        if replacesExistingExtension, !(name as NSString).pathExtension.isEmpty {
            name = (name as NSString).deletingPathExtension
        } else if !(name as NSString).pathExtension.isEmpty {
            return name
        }
        return (name as NSString).appendingPathExtension(fallbackExtension) ?? "\(name).\(fallbackExtension)"
    }

    private func readableLocalSource(for request: AppImagePreviewRequest) -> URL? {
        guard case .fileURL(let url) = request.source,
              fileManager.isReadableFile(atPath: url.path) else {
            return nil
        }
        return url.standardizedFileURL
    }

    private static func allowedContentTypes(forOriginalExtension pathExtension: String) -> [UTType]? {
        let normalized = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let type = UTType(filenameExtension: normalized),
              type.conforms(to: .image) else {
            return nil
        }
        return [type]
    }
}

@MainActor
private struct AppImagePreviewSavePanelPicker {
    func destination(for request: AppImagePreviewSaveDestinationRequest) async -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = request.suggestedFileName
        if let allowedContentTypes = request.allowedContentTypes {
            panel.allowedContentTypes = allowedContentTypes
        }
        // The image preview is presented in a child overlay window; attach sheets to
        // the parent app window so system panels do not anchor to the overlay chrome.
        let sheetWindow = NSApp.keyWindow?.parent ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let window = sheetWindow else {
            return panel.runModal() == .OK ? panel.url : nil
        }
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}

enum AppImagePreviewSaveError: LocalizedError, Equatable {
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .pngEncodingFailed:
            return "The image could not be encoded for saving."
        }
    }
}

extension AppImagePreviewLoadedImage {
    func pngData() throws -> Data {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw AppImagePreviewSaveError.pngEncodingFailed
        }
        return data
    }
}
