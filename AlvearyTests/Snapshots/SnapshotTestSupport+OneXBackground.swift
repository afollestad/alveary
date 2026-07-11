import AppKit

func copySnapshotBitmap(_ source: NSBitmapImageRep) -> NSBitmapImageRep? {
    guard let sourceData = source.bitmapData,
          let copy = NSBitmapImageRep(
              bitmapDataPlanes: nil,
              pixelsWide: source.pixelsWide,
              pixelsHigh: source.pixelsHigh,
              bitsPerSample: 8,
              samplesPerPixel: 4,
              hasAlpha: true,
              isPlanar: false,
              colorSpaceName: .deviceRGB,
              bitmapFormat: [],
              bytesPerRow: 0,
              bitsPerPixel: 0
          ),
          let copyData = copy.bitmapData else {
        return nil
    }
    let rowByteCount = min(source.bytesPerRow, copy.bytesPerRow)
    for row in 0..<source.pixelsHigh {
        copyData.advanced(by: row * copy.bytesPerRow).update(
            from: sourceData.advanced(by: row * source.bytesPerRow),
            count: rowByteCount
        )
    }
    copy.size = source.size
    return copy
}

func snapshotImageCopyingBitmapData(from bitmap: NSBitmapImageRep, size: CGSize) -> NSImage? {
    guard let bitmapData = bitmap.bitmapData,
          let context = CGContext(
              data: bitmapData,
              width: bitmap.pixelsWide,
              height: bitmap.pixelsHigh,
              bitsPerComponent: 8,
              bytesPerRow: bitmap.bytesPerRow,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let image = context.makeImage() else {
        return nil
    }
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = size
    let snapshot = NSImage(size: size)
    snapshot.addRepresentation(representation)
    return snapshot
}

func snapshotCornerBackgroundPixel(in bitmap: NSBitmapImageRep) -> SnapshotPixel? {
    guard bitmap.pixelsWide > 0,
          bitmap.pixelsHigh > 0,
          bitmap.bitsPerPixel == 32,
          bitmap.bitsPerSample == 8,
          let bitmapData = bitmap.bitmapData else {
        return nil
    }
    let corners = [
        snapshotPixel(in: bitmapData, column: 0, row: 0, bytesPerRow: bitmap.bytesPerRow),
        snapshotPixel(
            in: bitmapData,
            column: bitmap.pixelsWide - 1,
            row: 0,
            bytesPerRow: bitmap.bytesPerRow
        ),
        snapshotPixel(
            in: bitmapData,
            column: 0,
            row: bitmap.pixelsHigh - 1,
            bytesPerRow: bitmap.bytesPerRow
        ),
        snapshotPixel(
            in: bitmapData,
            column: bitmap.pixelsWide - 1,
            row: bitmap.pixelsHigh - 1,
            bytesPerRow: bitmap.bytesPerRow
        )
    ]
    return corners.first { candidate in
        corners.filter { $0 == candidate }.count >= 3
    }
}

func replaceSnapshotPixels(
    matching source: SnapshotPixel,
    with replacement: SnapshotPixel,
    in bitmap: NSBitmapImageRep
) {
    guard let bitmapData = bitmap.bitmapData else {
        return
    }
    for row in 0..<bitmap.pixelsHigh {
        for column in 0..<bitmap.pixelsWide {
            let offset = row * bitmap.bytesPerRow + column * 4
            guard snapshotPixel(
                in: bitmapData,
                column: column,
                row: row,
                bytesPerRow: bitmap.bytesPerRow
            ) == source else {
                continue
            }
            bitmapData[offset] = replacement.red
            bitmapData[offset + 1] = replacement.green
            bitmapData[offset + 2] = replacement.blue
            bitmapData[offset + 3] = replacement.alpha
        }
    }
}

struct SnapshotPixel: Equatable {
    // Transparent black is storage-order agnostic: it remains valid whether AppKit
    // supplies alpha-first or alpha-last 32-bit bitmap data.
    static let canonicalBackground = SnapshotPixel(red: 0, green: 0, blue: 0, alpha: 0)

    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private func snapshotPixel(
    in bitmapData: UnsafeMutablePointer<UInt8>,
    column: Int,
    row: Int,
    bytesPerRow: Int
) -> SnapshotPixel {
    let offset = row * bytesPerRow + column * 4
    return SnapshotPixel(
        red: bitmapData[offset],
        green: bitmapData[offset + 1],
        blue: bitmapData[offset + 2],
        alpha: bitmapData[offset + 3]
    )
}
