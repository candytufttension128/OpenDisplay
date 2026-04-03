import AppKit
import CoreGraphics

/// Overlay-based dimming — black window over display
class OverlayDimmer {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]

    func setDimming(opacity: CGFloat, for displayID: CGDirectDisplayID) {
        let op = max(0, min(1, opacity))
        if op <= 0 { removeOverlay(for: displayID); return }
        if let w = windows[displayID] { w.backgroundColor = .black.withAlphaComponent(op); return }
        guard let screen = screen(for: displayID) else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .screenSaver; w.backgroundColor = .black.withAlphaComponent(op)
        w.isOpaque = false; w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary]
        w.orderFrontRegardless()
        windows[displayID] = w
    }

    func removeOverlay(for displayID: CGDirectDisplayID) {
        windows[displayID]?.close(); windows.removeValue(forKey: displayID)
    }

    func removeAll() { windows.values.forEach { $0.close() }; windows.removeAll() }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }
}
