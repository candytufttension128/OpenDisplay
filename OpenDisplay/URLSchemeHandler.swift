import AppKit
import Foundation

/// URL scheme handler: opendisplay://command/value?display=N
/// Examples:
///   opendisplay://brightness/80
///   opendisplay://contrast/50?display=1
///   opendisplay://input/hdmi1
///   opendisplay://volume/30
///   opendisplay://power/off
///   opendisplay://nightshift/on
///   opendisplay://tile/left
class URLSchemeHandler {
    static let scheme = "opendisplay"

    static func handle(url: URL) {
        guard url.scheme == scheme else { return }
        let command = url.host ?? ""
        let value = url.pathComponents.count > 1 ? url.pathComponents[1] : ""
        let params = parseQuery(url.query)
        let displayIndex = Int(params["display"] ?? "0") ?? 0

        let mgr = DisplayManager()
        guard displayIndex < mgr.displays.count else { return }
        let displayID = mgr.displays[displayIndex].id

        switch command {
        case "brightness":
            if let v = UInt16(value) { DDCControl.write(command: .brightness, value: v, for: displayID) }
        case "contrast":
            if let v = UInt16(value) { DDCControl.write(command: .contrast, value: v, for: displayID) }
        case "volume":
            if let v = UInt16(value) { DDCControl.write(command: .volume, value: v, for: displayID) }
        case "input":
            let map: [String: DDCInputSource] = [
                "hdmi1": .hdmi1, "hdmi2": .hdmi2, "dp1": .dp1, "dp2": .dp2,
                "usbc": .usbc, "vga": .vga1, "dvi": .dvi1
            ]
            if let src = map[value.lowercased()] {
                DDCControl.write(command: .inputSource, value: src.rawValue, for: displayID)
            }
        case "power":
            let map: [String: DDCPowerMode] = ["on": .on, "standby": .standby, "off": .off]
            if let mode = map[value.lowercased()] {
                DDCControl.write(command: .powerMode, value: mode.rawValue, for: displayID)
            }
        case "tile":
            let tileMap: [String: WindowTiler.TilePosition] = [
                "left": .left, "right": .right, "top": .top, "bottom": .bottom,
                "topleft": .topLeft, "topright": .topRight,
                "bottomleft": .bottomLeft, "bottomright": .bottomRight,
                "maximize": .maximize, "center": .center
            ]
            if let pos = tileMap[value.lowercased()], let screen = NSScreen.main?.visibleFrame {
                let frame = pos.frame(in: screen)
                guard let app = NSWorkspace.shared.frontmostApplication else { return }
                let appRef = AXUIElementCreateApplication(app.processIdentifier)
                var winRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &winRef) == .success else { return }
                let win = winRef as! AXUIElement
                var p = CGPoint(x: frame.origin.x, y: NSScreen.screens[0].frame.height - frame.maxY)
                var s = CGSize(width: frame.width, height: frame.height)
                if let pv = AXValueCreate(.cgPoint, &p) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, pv) }
                if let sv = AXValueCreate(.cgSize, &s) { AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, sv) }
            }
        case "profile":
            if let profile = ProfileManager.shared.profiles.first(where: { $0.name == value }) {
                if let b = profile.brightness { DDCControl.write(command: .brightness, value: UInt16(b), for: displayID) }
                if let c = profile.contrast { DDCControl.write(command: .contrast, value: UInt16(c), for: displayID) }
                if let v = profile.volume { DDCControl.write(command: .volume, value: UInt16(v), for: displayID) }
            }
        default: break
        }
    }

    private static func parseQuery(_ query: String?) -> [String: String] {
        guard let query else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { result[String(kv[0])] = String(kv[1]) }
        }
        return result
    }
}
