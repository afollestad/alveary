import Foundation

enum ComposerAttachment: Equatable, Identifiable {
    case image(LocalImageAttachment)
    case file(LocalFileAttachment)
    case appShot(AppShotAttachment)

    var id: String {
        switch self {
        case .image(let attachment):
            return attachment.id
        case .file(let attachment):
            return attachment.id
        case .appShot(let appShot):
            return appShot.id
        }
    }
}
