import CoreGraphics
import AppKit

/// Soft disconnect/reconnect displays without physically unplugging
/// Uses CGDisplay configuration APIs to disable/enable displays
class DisplaySoftDisconnect {
    private var disconnectedDisplays: Set<CGDirectDisplayID> = []

    /// Soft-disconnect a display (turns it off in macOS, screen goes black)
    func disconnect(_ displayID: CGDirectDisplayID) {
        // Use overlay to black out + prevent sleep assertion
        let overlay = OverlayDimmer()
        overlay.setDimming(opacity: 1.0, for: displayID)
        disconnectedDisplays.insert(displayID)

        // Also power off via DDC if external
        if CGDisplayIsBuiltin(displayID) == 0 {
            DDCControl.write(command: .powerMode, value: DDCPowerMode.standby.rawValue, for: displayID)
        }
    }

    /// Reconnect a soft-disconnected display
    func reconnect(_ displayID: CGDirectDisplayID) {
        let overlay = OverlayDimmer()
        overlay.removeOverlay(for: displayID)
        disconnectedDisplays.remove(displayID)

        if CGDisplayIsBuiltin(displayID) == 0 {
            DDCControl.write(command: .powerMode, value: DDCPowerMode.on.rawValue, for: displayID)
        }
    }

    func isDisconnected(_ displayID: CGDirectDisplayID) -> Bool {
        disconnectedDisplays.contains(displayID)
    }

    func reconnectAll() {
        for id in disconnectedDisplays { reconnect(id) }
    }
}
