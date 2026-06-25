@preconcurrency import AppKit
import CoreGraphics
import Foundation

struct AppShotSystemSettingsWindowSnapshot: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
}

enum AppShotSystemSettingsWindowLocator {
    private static let bundleIdentifier = "com.apple.systempreferences"

    static func frontmostWindow() -> AppShotSystemSettingsWindowSnapshot? {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], .zero) as? [[String: Any]]
        else {
            return nil
        }

        let windows = windowInfo.compactMap { info -> AppShotSystemSettingsWindowSnapshot? in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == app.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = cgFrame(from: bounds) else {
                return nil
            }

            let geometry = appKitGeometry(from: frame)
            guard geometry.frame.width > 320, geometry.frame.height > 240 else {
                return nil
            }
            return AppShotSystemSettingsWindowSnapshot(
                frame: geometry.frame,
                visibleFrame: geometry.visibleFrame
            )
        }

        return windows.max { lhs, rhs in
            lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
        }
    }

    private static func cgFrame(from bounds: [String: Any]) -> CGRect? {
        guard let originX = cgFloat(bounds["X"]),
              let originY = cgFloat(bounds["Y"]),
              let width = cgFloat(bounds["Width"]),
              let height = cgFloat(bounds["Height"]) else {
            return nil
        }
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat {
            return value
        }
        if let value = value as? Double {
            return CGFloat(value)
        }
        if let value = value as? Int {
            return CGFloat(value)
        }
        return (value as? NSNumber).map { CGFloat(truncating: $0) }
    }

    private static func appKitGeometry(from cgFrame: CGRect) -> (frame: CGRect, visibleFrame: CGRect) {
        let screens = NSScreen.screens.compactMap { screen -> AppShotScreenGeometry? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return AppShotScreenGeometry(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                cgBounds: CGDisplayBounds(displayID)
            )
        }

        let matchedScreen = screens
            .filter { $0.cgBounds.intersects(cgFrame) }
            .max { lhs, rhs in
                lhs.cgBounds.intersection(cgFrame).width * lhs.cgBounds.intersection(cgFrame).height
                    < rhs.cgBounds.intersection(cgFrame).width * rhs.cgBounds.intersection(cgFrame).height
            }

        guard let matchedScreen else {
            return (
                frame: cgFrame,
                visibleFrame: NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: cgFrame.size)
            )
        }

        let localX = cgFrame.minX - matchedScreen.cgBounds.minX
        let localY = cgFrame.minY - matchedScreen.cgBounds.minY
        return (
            frame: CGRect(
                x: matchedScreen.frame.minX + localX,
                y: matchedScreen.frame.maxY - localY - cgFrame.height,
                width: cgFrame.width,
                height: cgFrame.height
            ),
            visibleFrame: matchedScreen.visibleFrame
        )
    }
}

private struct AppShotScreenGeometry {
    let frame: CGRect
    let visibleFrame: CGRect
    let cgBounds: CGRect
}
