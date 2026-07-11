@preconcurrency import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum AppShotScreenshotCapturer {
    static func captureScreenshotData(for target: AppShotWindowTarget) async throws -> Data {
        guard AppShotPermission.screenRecording.isAllowed else {
            throw AppShotCaptureError.screenRecordingPermissionMissing
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = bestMatchingWindow(for: target, in: content.windows) else {
            throw AppShotCaptureError.noReliableScreenCaptureMatch
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(Int(window.frame.width.rounded()), 1)
        configuration.height = max(Int(window.frame.height.rounded()), 1)
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let data = pngData(from: image) else {
            throw AppShotCaptureError.screenshotEncodingFailed
        }
        return data
    }

    private static func bestMatchingWindow(for target: AppShotWindowTarget, in windows: [SCWindow]) -> SCWindow? {
        let candidates = windows.filter { window in
            window.owningApplication?.processID == target.processIdentifier
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let scored = candidates.map { window in
            (window: window, score: matchScore(window: window, target: target))
        }
        guard let best = scored.min(by: { lhs, rhs in lhs.score < rhs.score }) else {
            return nil
        }
        guard isReliableMatch(window: best.window, target: target, score: best.score, candidateCount: candidates.count) else {
            return nil
        }
        return best.window
    }

    private static func matchScore(window: SCWindow, target: AppShotWindowTarget) -> Double {
        var score = 0.0
        if !target.windowTitle.isEmpty, window.title != target.windowTitle {
            score += 200
        }
        guard let bounds = target.windowBounds else {
            return score
        }
        score += abs(window.frame.minX - bounds.minX)
        score += abs(window.frame.minY - bounds.minY)
        score += abs(window.frame.width - bounds.width)
        score += abs(window.frame.height - bounds.height)
        return score
    }

    private static func isReliableMatch(
        window: SCWindow,
        target: AppShotWindowTarget,
        score: Double,
        candidateCount: Int
    ) -> Bool {
        let titleMatches = target.windowTitle.isEmpty || window.title == target.windowTitle
        if let bounds = target.windowBounds {
            let boundsDistance = abs(window.frame.minX - bounds.minX) +
                abs(window.frame.minY - bounds.minY) +
                abs(window.frame.width - bounds.width) +
                abs(window.frame.height - bounds.height)
            return boundsDistance <= 24 || (titleMatches && score <= 24)
        }
        return titleMatches || (candidateCount == 1 && target.windowTitle.isEmpty)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: image)
        return representation.representation(using: .png, properties: [:])
    }
}
