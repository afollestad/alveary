import AppKit
@preconcurrency import SnapshotTesting
import SwiftUI
import XCTest

@testable import Alveary

/// Default precision parameters applied to every `assertMacSnapshot` call. `0.99`
/// corresponds to the Delta-E threshold SnapshotTesting documents as "mimics the
/// precision of the human eye". The library's hard default of `1.0`/`1.0` requires a
/// bit-exact decoded-pixel match, which Core Graphics' color-managed PNG decode path
/// does not deliver reliably — tiny per-channel rounding differences survive the
/// encoder round trip on larger, color-rich baselines (diff viewer with syntax
/// highlighting, settings screens, composer autocomplete at scroll offset) even when
/// the pixels are sub-visually identical to the baseline, and baselines have been
/// re-recorded more than once with no code change. Both knobs need to move together:
/// `perceptualPrecision` sets the per-pixel Delta-E tolerance, but with `precision` at
/// `1.0` the test still fails if even one pixel exceeds it; lowering `precision` to
/// `0.99` admits up to 1% of pixels crossing the Delta-E line, which is where
/// channel-rounding drift tends to spread. Together they absorb sub-visible encoder
/// noise without giving up coverage of anything a reviewer could actually see.
/// Override per call site if a specific test wants stricter or looser matching, but do
/// not tighten these shared values: the drift class is not specific to one baseline, so
/// raising them brings it back for every large, color-rich image at once.
let defaultPixelPrecision: Float = 0.99
let defaultPerceptualPrecision: Float = 0.99
private let appKitSnapshotScale: CGFloat = 2
// The environment override intentionally simulates this cross-renderer fallback.
// Per-call `forceFixedScale` snapshots remain at their caller-provided precision.
private let automaticOneXFallbackPrecision: Float = 0.9

struct SnapshotComparisonPrecision: Equatable {
    let pixel: Float
    let perceptual: Float
}

func fixedScaleSnapshotComparisonPrecision(
    precision: Float,
    perceptualPrecision: Float,
    relaxesForAutomaticOneXFallback: Bool
) -> SnapshotComparisonPrecision {
    guard relaxesForAutomaticOneXFallback else {
        return SnapshotComparisonPrecision(pixel: precision, perceptual: perceptualPrecision)
    }
    return SnapshotComparisonPrecision(
        pixel: min(precision, automaticOneXFallbackPrecision),
        perceptual: min(perceptualPrecision, automaticOneXFallbackPrecision)
    )
}

/// Picks the renderer for one comparison: SnapshotTesting's native AppKit path on a Retina
/// display, and a fixed-scale capture when headless CI exposes only a 1x screen. The 1x path
/// normalizes the stored 2x reference in memory rather than expecting a 1x baseline, which is
/// why baselines stay recorded at 2x and must never be re-recorded against a 1x runner.
func macSnapshotImage(
    precision: Float = defaultPixelPrecision,
    perceptualPrecision: Float = defaultPerceptualPrecision,
    forceFixedScale: Bool = false
) -> Snapshotting<NSViewController, NSImage> {
    if usesNativeSnapshotRenderer, !forceFixedScale {
        return .image(precision: precision, perceptualPrecision: perceptualPrecision)
    }
    let usesOneXFallback = usesAutomaticOneXFallback(
        forceFixedScale: forceFixedScale,
        isFixedScaleRendererForced: isFixedScaleSnapshotRendererForced,
        screenScale: NSScreen.main?.backingScaleFactor ?? 1
    )
    let comparisonPrecision = fixedScaleSnapshotComparisonPrecision(
        precision: precision,
        perceptualPrecision: perceptualPrecision,
        relaxesForAutomaticOneXFallback: usesOneXFallback
    )
    let diffing = snapshotImageDiffing(
        precision: comparisonPrecision.pixel,
        perceptualPrecision: comparisonPrecision.perceptual,
        normalizesToOneX: usesOneXFallback
    )
    return Snapshotting(pathExtension: "png", diffing: diffing) { controller in
        MainActor.assumeIsolated {
            renderFixedScaleSnapshotImage(
                for: controller.view,
                usesOneXFallback: usesOneXFallback
            )
        }
    }
}

private var usesNativeSnapshotRenderer: Bool {
    !isFixedScaleSnapshotRendererForced
        && (NSScreen.main?.backingScaleFactor ?? 1) >= appKitSnapshotScale
}

private var isFixedScaleSnapshotRendererForced: Bool {
    ProcessInfo.processInfo.environment["ALVEARY_FORCE_FIXED_SCALE_SNAPSHOTS"] == "true"
}

func usesAutomaticOneXFallback(
    forceFixedScale: Bool,
    isFixedScaleRendererForced: Bool,
    screenScale: CGFloat
) -> Bool {
    !forceFixedScale && (isFixedScaleRendererForced || screenScale < appKitSnapshotScale)
}

@MainActor
private func renderFixedScaleSnapshotImage(
    for view: NSView,
    usesOneXFallback: Bool
) -> NSImage {
    let bounds = view.bounds
    guard bounds.width > 0, bounds.height > 0 else {
        fatalError("View not renderable to image at size \(bounds.size)")
    }
    // Direct higher-scale caching can drop lazy SwiftUI List subviews. Capture at the
    // display's native scale so every visible row reaches the snapshot, then normalize
    // the reference during comparison when the display can only produce a 1× image.
    guard let sourceRep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
        fatalError("Unable to create native snapshot representation at size \(bounds.size)")
    }
    view.cacheDisplay(in: bounds, to: sourceRep)
    let capturedImage = NSImage(size: bounds.size)
    capturedImage.addRepresentation(sourceRep)

    let targetPixelsWide = Int(bounds.width * appKitSnapshotScale)
    let targetPixelsHigh = Int(bounds.height * appKitSnapshotScale)
    if usesOneXFallback {
        guard sourceRep.pixelsWide > Int(bounds.width) || sourceRep.pixelsHigh > Int(bounds.height),
              let sourceImage = sourceRep.cgImage else {
            return capturedImage
        }
        return renderSnapshotImage(sourceImage, in: bounds, scale: 1)
    }
    if sourceRep.pixelsWide == targetPixelsWide, sourceRep.pixelsHigh == targetPixelsHigh {
        return capturedImage
    }

    guard let imageToScale = sourceRep.cgImage else {
        fatalError("Unable to create native snapshot image at size \(bounds.size)")
    }
    return renderSnapshotImage(imageToScale, in: bounds, scale: appKitSnapshotScale)
}

private func snapshotImageDiffing(
    precision: Float,
    perceptualPrecision: Float,
    normalizesToOneX: Bool
) -> Diffing<NSImage> {
    let imageDiffing = Diffing<NSImage>.image(
        precision: precision,
        perceptualPrecision: perceptualPrecision
    )
    guard normalizesToOneX else {
        return imageDiffing
    }
    return .diff(
        toData: imageDiffing.toData,
        fromData: imageDiffing.fromData
    ) { reference, failure in
        MainActor.assumeIsolated {
            let images = oneXSnapshotImagesNormalizingCornerBackground(
                reference: reference,
                failure: failure
            )
            return imageDiffing.diffV2(
                images.reference,
                images.failure
            )
        }
    }
}

@MainActor
func oneXSnapshotImagesNormalizingCornerBackground(
    reference: NSImage,
    failure: NSImage
) -> (reference: NSImage, failure: NSImage) {
    guard let referenceImage = oneXSnapshotImage(reference),
          let failureImage = oneXSnapshotImage(failure) else {
        return (reference, failure)
    }
    let referenceBackgroundPixel = snapshotCornerBackgroundPixel(in: referenceImage.bitmap)
    let failureBackgroundPixel = snapshotCornerBackgroundPixel(in: failureImage.bitmap)
    guard referenceImage.bitmap.pixelsWide == failureImage.bitmap.pixelsWide,
          referenceImage.bitmap.pixelsHigh == failureImage.bitmap.pixelsHigh,
          let referenceBackground = referenceBackgroundPixel,
          let failureBackground = failureBackgroundPixel,
          referenceBackground != failureBackground else {
        return (
            snapshotImage(from: referenceImage.bitmap, size: referenceImage.size),
            snapshotImage(from: failureImage.bitmap, size: failureImage.size)
        )
    }
    guard let normalizedReference = copySnapshotBitmap(referenceImage.bitmap),
          let normalizedFailure = copySnapshotBitmap(failureImage.bitmap) else {
        return (
            snapshotImage(from: referenceImage.bitmap, size: referenceImage.size),
            snapshotImage(from: failureImage.bitmap, size: failureImage.size)
        )
    }

    replaceSnapshotPixels(
        matching: referenceBackground,
        with: .canonicalBackground,
        in: normalizedReference
    )
    replaceSnapshotPixels(
        matching: failureBackground,
        with: .canonicalBackground,
        in: normalizedFailure
    )
    guard let normalizedReferenceImage = snapshotImageCopyingBitmapData(
        from: normalizedReference,
        size: referenceImage.size
    ),
        let normalizedFailureImage = snapshotImageCopyingBitmapData(
            from: normalizedFailure,
            size: failureImage.size
        ) else {
        return (
            snapshotImage(from: referenceImage.bitmap, size: referenceImage.size),
            snapshotImage(from: failureImage.bitmap, size: failureImage.size)
        )
    }
    return (normalizedReferenceImage, normalizedFailureImage)
}

@MainActor
private func oneXSnapshotImage(_ image: NSImage) -> (bitmap: NSBitmapImageRep, size: CGSize)? {
    guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
    }
    let bounds = CGRect(origin: .zero, size: image.size)
    return (renderSnapshotRepresentation(sourceImage, in: bounds, scale: 1), bounds.size)
}

@MainActor
private func renderSnapshotImage(
    _ sourceImage: CGImage,
    in bounds: CGRect,
    scale: CGFloat
) -> NSImage {
    let bitmapRep = renderSnapshotRepresentation(sourceImage, in: bounds, scale: scale)
    return snapshotImage(from: bitmapRep, size: bounds.size)
}

private func snapshotImage(from bitmap: NSBitmapImageRep, size: CGSize) -> NSImage {
    let image = NSImage(size: size)
    image.addRepresentation(bitmap)
    return image
}

@MainActor
private func configureSnapshotWindow(
    _ window: NSWindow,
    controller: NSViewController,
    appearanceName: NSAppearance.Name
) {
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: appearanceName)
    window.backgroundColor = .windowBackgroundColor
    window.contentViewController = controller
}

@MainActor
func closeSnapshotWindow(
    _ window: NSWindow,
    controller: NSHostingController<AnyView>
) {
    // Replacing the root while it is still window-attached starts tearing down SwiftUI's
    // `@Query` observations. Detaching the controller alone can leave
    // those observations registered until a later context save on macOS 26.
    controller.rootView = AnyView(EmptyView())
    controller.view.layoutSubtreeIfNeeded()
    window.contentViewController = nil
    window.contentView = nil
    window.close()
}

@MainActor
private func renderSnapshotRepresentation(
    _ sourceImage: CGImage,
    in bounds: CGRect,
    scale: CGFloat
) -> NSBitmapImageRep {
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(bounds.width * scale),
        pixelsHigh: Int(bounds.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create snapshot bitmap representation at size \(bounds.size)")
    }
    bitmapRep.size = bounds.size
    guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
        fatalError("Unable to create snapshot graphics context at size \(bounds.size)")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.interpolationQuality = .high
    context.cgContext.draw(sourceImage, in: bounds)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return bitmapRep
}

/// Renders `makeView` into a real `NSWindow` and compares it against the stored baseline.
///
/// The window is not incidental. A bare `NSHostingController` with no window display pass
/// captures sidebar `List` content with custom section headers as a blank background, so the
/// hosting controller must be installed in a window and driven through `displayIfNeeded()`.
///
/// `colorScheme` sets the SwiftUI environment *and* the hosting `NSAppearance` together; a
/// dark-mode snapshot that moves only one of them renders AppKit-backed colors such as
/// `separatorColor` for the wrong appearance.
///
/// Use `assertMacModelSnapshot` instead when the view reads `@Query` — this helper returns
/// before SwiftData observations finish unregistering.
@MainActor
func assertMacSnapshot<V: View>(
    _ makeView: @autoclosure () -> V,
    size: CGSize,
    named: String? = nil,
    colorScheme: ColorScheme = .light,
    precision: Float = defaultPixelPrecision,
    perceptualPrecision: Float = defaultPerceptualPrecision,
    forceFixedScale: Bool = false,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    autoreleasepool {
        let view = makeView()
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua

        let rootView = view
            .transaction { $0.animation = nil }
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0) ?? .current)
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.colorScheme, colorScheme)
            // Spinner animations start from `onAppear` and would capture a
            // time-dependent arc angle; the outer `transaction` override cannot
            // suppress the spinner's own `.animation(_:value:)` modifier.
            .environment(\.statusSpinnerAnimationsDisabled, true)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))

        let controller = NSHostingController(rootView: AnyView(rootView))
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: appearanceName)
        // Position the snapshot window far off-screen so the real cursor position cannot
        // land inside its bounds and trigger hover effects on controls (e.g. a Picker
        // rendering a hovered background behind its selected label). Without this the
        // off-screen window still sits in the primary-display coordinate space and picks
        // up the global mouse position mid-render, producing flaky snapshots.
        let offscreenOrigin = CGPoint(x: -size.width - 1000, y: -size.height - 1000)
        let window = NSWindow(
            contentRect: CGRect(origin: offscreenOrigin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        configureSnapshotWindow(window, controller: controller, appearanceName: appearanceName)
        defer { closeSnapshotWindow(window, controller: controller) }
        // Explicitly clear first responder so no control in the hierarchy begins the
        // render with a focus ring. NSHostingController can settle on an initial first
        // responder during `layoutIfNeeded()`; flushing it before `displayIfNeeded()`
        // produces a deterministic, focus-free baseline.
        window.makeFirstResponder(nil)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()

        XCTAssertEqual(
            controller.view.bounds.size,
            size,
            "Snapshot host laid out at an unexpected size",
            file: file,
            line: line
        )

        assertSnapshot(
            of: controller,
            as: macSnapshotImage(
                precision: precision,
                perceptualPrecision: perceptualPrecision,
                forceFixedScale: forceFixedScale
            ),
            named: named,
            record: ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1" ? true : nil,
            file: file,
            testName: testName,
            line: line
        )
    }
}
