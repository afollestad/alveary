import BlockInputKit
import Foundation

extension AppKitMarkdownLayoutMeasurer {
    /// Resolves the same natural size `AppKitMarkdownImageBlockView` will draw
    /// at; measuring the raw image would reserve the 16:9 fallback for every
    /// source that declares no dimensions.
    func measureImage(
        _ image: BlockInputImage,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let naturalSize = imageStore.naturalSize(for: image, baseURL: imageBaseURL)
        let displaySize = appMarkdownImageDisplaySize(
            for: image.appMarkdownResolved(naturalSize: naturalSize),
            constrainedTo: width
        )
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: displaySize.height,
            naturalContentWidth: displaySize.width,
            fallbackRequired: false
        )
    }
}
