import CoreGraphics
import AppKit

struct DisplayInfo: Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32
    let rotation: Double
    let currentMode: CGDisplayMode?
    let availableModes: [CGDisplayMode]
}

struct DisplayMode: Identifiable, Hashable {
    let id: Int32
    let width: Int
    let height: Int
    let refreshRate: Double
    let isHiDPI: Bool
    let pixelWidth: Int
    let pixelHeight: Int

    var label: String {
        let suffix = isHiDPI ? " (HiDPI)" : ""
        let hz = refreshRate > 0 ? " @ \(Int(refreshRate))Hz" : ""
        return "\(width) × \(height)\(hz)\(suffix)"
    }

    static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

class DisplayManager: ObservableObject {
    @Published var displays: [DisplayInfo] = []

    init() { refresh() }

    func refresh() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        displays = (0..<Int(count)).map { i in
            let id = ids[i]
            return DisplayInfo(
                id: id, name: screenName(for: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                vendorNumber: CGDisplayVendorNumber(id),
                modelNumber: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                rotation: CGDisplayRotation(id),
                currentMode: CGDisplayCopyDisplayMode(id),
                availableModes: allModes(for: id)
            )
        }
    }

    func allModes(for displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        return (CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode]) ?? []
    }

    func parsedModes(for display: DisplayInfo) -> [DisplayMode] {
        display.availableModes.map { m in
            DisplayMode(id: m.ioDisplayModeID, width: m.width, height: m.height,
                        refreshRate: m.refreshRate, isHiDPI: m.pixelWidth > m.width,
                        pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight)
        }.sorted { ($0.width, $0.height) > ($1.width, $1.height) }
    }

    func refreshRates(for display: DisplayInfo) -> [Double] {
        Array(Set(display.availableModes.map { $0.refreshRate }).filter { $0 > 0 }).sorted(by: >)
    }

    func setMode(_ mode: DisplayMode, for displayID: CGDirectDisplayID) {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode],
              let target = modes.first(where: { $0.ioDisplayModeID == mode.id }) else { return }
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayWithDisplayMode(config, displayID, target, nil)
        CGCompleteDisplayConfiguration(config, .permanently)
        refresh()
    }

    func setMirror(source: CGDirectDisplayID, target: CGDirectDisplayID, enabled: Bool) {
        var config: CGDisplayConfigRef?
        CGBeginDisplayConfiguration(&config)
        CGConfigureDisplayMirrorOfDisplay(config, target, enabled ? source : kCGNullDirectDisplay)
        CGCompleteDisplayConfiguration(config, .permanently)
        refresh()
    }

    private func screenName(for displayID: CGDirectDisplayID) -> String {
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               id == displayID { return screen.localizedName }
        }
        return CGDisplayIsBuiltin(displayID) != 0 ? "Built-in Display" : "External Display"
    }
}
