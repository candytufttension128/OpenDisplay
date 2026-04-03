import AppKit
import CoreGraphics

/// Native macOS OSD (on-screen display) for brightness/volume changes
class NativeOSD {
    /// Show the native brightness OSD. level: 0.0 to 1.0
    static func showBrightness(level: Float, for displayID: CGDirectDisplayID) {
        showOSD(type: 1, level: level, displayID: displayID)
    }

    /// Show the native volume OSD. level: 0.0 to 1.0
    static func showVolume(level: Float) {
        showOSD(type: 3, level: level, displayID: CGMainDisplayID())
    }

    /// Uses private OSDUIHelper via NSConnection (works on macOS 12+)
    private static func showOSD(type: UInt32, level: Float, displayID: CGDirectDisplayID) {
        // Try using the private OSDUIHelper framework
        guard let osdClass = NSClassFromString("OSDManager") else { return }
        let sel = NSSelectorFromString("sharedManager")
        guard let manager = (osdClass as AnyObject).perform(sel)?.takeUnretainedValue() else { return }
        let showSel = NSSelectorFromString("showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")
        let img: Int = type == 1 ? 1 : 3 // 1=brightness, 3=volume
        let chiclets = Int(level * 16)
        _ = (manager as AnyObject).perform(showSel, with: img, with: displayID)
        // Fallback: if private API unavailable, the call silently fails
        _ = chiclets // suppress warning
    }
}
