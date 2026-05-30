import BlockInputKit
import Foundation

extension AppKitMarkdownLayoutMeasurer {
    func measureImage(
        _ image: BlockInputImage,
        width: CGFloat
    ) -> AppKitMarkdownLayoutMeasurement {
        let displaySize = appMarkdownImageDisplaySize(for: image, constrainedTo: width)
        return AppKitMarkdownLayoutMeasurement(
            contentHeight: displaySize.height,
            naturalContentWidth: displaySize.width,
            fallbackRequired: false
        )
    }
}
