@preconcurrency import AppKit
import Foundation

@MainActor
final class AppShotAppBundleDragSourceView: NSView, NSPasteboardItemDataProvider, NSDraggingSource {
    private let bundleURL: URL
    private let rowView = NSView()
    private let label = NSTextField(labelWithString: "")

    init(bundle: Bundle = .main) {
        bundleURL = bundle.bundleURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup(bundle: bundle)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setDataProvider(self, forTypes: [.fileURL])

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(convert(rowView.bounds, from: rowView), contents: draggingImage())

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .fileURL else {
            return
        }
        item.setData(bundleURL.dataRepresentation, forType: .fileURL)
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        rowView.isHidden = true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        rowView.isHidden = false
    }

    private func setup(bundle: Bundle) {
        rowView.wantsLayer = true
        rowView.layer?.cornerRadius = 7
        rowView.layer?.borderWidth = 1
        rowView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowView)

        let iconBackground = NSView()
        iconBackground.wantsLayer = true
        iconBackground.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        iconBackground.layer?.cornerRadius = 6
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(iconBackground)

        let icon = NSWorkspace.shared.icon(forFile: bundle.bundleURL.path)
        icon.size = NSSize(width: 44, height: 44)
        let iconView = NSImageView(image: icon)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconBackground.addSubview(iconView)

        label.stringValue = appDisplayName(bundle: bundle)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = NSColor.labelColor.withAlphaComponent(0.84)
        label.translatesAutoresizingMaskIntoConstraints = false
        rowView.addSubview(label)

        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowView.topAnchor.constraint(equalTo: topAnchor),
            rowView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconBackground.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 10),
            iconBackground.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 25),
            iconBackground.heightAnchor.constraint(equalToConstant: 25),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 21),
            iconView.heightAnchor.constraint(equalToConstant: 21),

            label.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: rowView.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: rowView.centerYAnchor)
        ])
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        rowView.layer?.backgroundColor = isDark
            ? NSColor.white.withAlphaComponent(0.07).cgColor
            : NSColor.white.withAlphaComponent(0.7).cgColor
        rowView.layer?.borderColor = isDark
            ? NSColor.white.withAlphaComponent(0.1).cgColor
            : NSColor.separatorColor.withAlphaComponent(0.45).cgColor
    }

    private func appDisplayName(bundle: Bundle) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? bundle.bundleURL.deletingPathExtension().lastPathComponent
    }

    private func draggingImage() -> NSImage {
        let bounds = rowView.bounds
        let image = NSImage(size: bounds.size)
        guard let bitmap = rowView.bitmapImageRepForCachingDisplay(in: bounds) else {
            return image
        }
        rowView.cacheDisplay(in: bounds, to: bitmap)
        image.addRepresentation(bitmap)
        return image
    }
}
