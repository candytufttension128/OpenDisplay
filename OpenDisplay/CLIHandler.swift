import Foundation

/// CLI interface for scripting and automation
/// Usage: OpenDisplay --brightness 80 --display 1
///        OpenDisplay --list
///        OpenDisplay --input hdmi1 --display 2
struct CLIHandler {
    static func handleArguments(_ args: [String]) -> Bool {
        guard args.count > 1 else { return false }
        let mgr = DisplayManager()
        var displayIndex = 0
        var i = 1

        while i < args.count {
            switch args[i] {
            case "--list":
                for (idx, d) in mgr.displays.enumerated() {
                    let edid = EDIDReader.read(for: d.id)
                    print("[\(idx)] \(d.name) (ID: \(d.id))")
                    print("    Built-in: \(d.isBuiltIn)")
                    print("    Vendor: \(d.vendorNumber) Model: \(d.modelNumber)")
                    if let e = edid { print("    EDID: \(e.manufacturerID) \(e.displayName ?? "Unknown")") }
                    if let mode = d.currentMode {
                        print("    Resolution: \(mode.width)x\(mode.height) @ \(Int(mode.refreshRate))Hz")
                    }
                }
                return true

            case "--display":
                i += 1; displayIndex = Int(args[i]) ?? 0

            case "--brightness":
                i += 1
                guard displayIndex < mgr.displays.count, let val = UInt16(args[i]) else { break }
                DDCControl.write(command: .brightness, value: val, for: mgr.displays[displayIndex].id)
                print("Brightness set to \(val)")

            case "--contrast":
                i += 1
                guard displayIndex < mgr.displays.count, let val = UInt16(args[i]) else { break }
                DDCControl.write(command: .contrast, value: val, for: mgr.displays[displayIndex].id)
                print("Contrast set to \(val)")

            case "--volume":
                i += 1
                guard displayIndex < mgr.displays.count, let val = UInt16(args[i]) else { break }
                DDCControl.write(command: .volume, value: val, for: mgr.displays[displayIndex].id)
                print("Volume set to \(val)")

            case "--input":
                i += 1
                guard displayIndex < mgr.displays.count else { break }
                let inputMap: [String: DDCInputSource] = [
                    "hdmi1": .hdmi1, "hdmi2": .hdmi2, "dp1": .dp1, "dp2": .dp2,
                    "usbc": .usbc, "vga": .vga1, "dvi": .dvi1
                ]
                if let src = inputMap[args[i].lowercased()] {
                    DDCControl.write(command: .inputSource, value: src.rawValue, for: mgr.displays[displayIndex].id)
                    print("Input set to \(src.label)")
                }

            case "--power":
                i += 1
                guard displayIndex < mgr.displays.count else { break }
                let powerMap: [String: DDCPowerMode] = ["on": .on, "standby": .standby, "off": .off]
                if let mode = powerMap[args[i].lowercased()] {
                    DDCControl.write(command: .powerMode, value: mode.rawValue, for: mgr.displays[displayIndex].id)
                    print("Power set to \(mode.label)")
                }

            case "--resolution":
                i += 1
                guard displayIndex < mgr.displays.count else { break }
                let parts = args[i].split(separator: "x").compactMap { Int($0) }
                guard parts.count == 2 else { break }
                let modes = mgr.parsedModes(for: mgr.displays[displayIndex])
                if let mode = modes.first(where: { $0.width == parts[0] && $0.height == parts[1] }) {
                    mgr.setMode(mode, for: mgr.displays[displayIndex].id)
                    print("Resolution set to \(mode.label)")
                }

            case "--modes":
                guard displayIndex < mgr.displays.count else { break }
                for mode in mgr.parsedModes(for: mgr.displays[displayIndex]) {
                    print("  \(mode.label) [id:\(mode.id)]")
                }
                return true

            case "--help":
                printUsage(); return true

            default: break
            }
            i += 1
        }
        return true
    }

    static func printUsage() {
        print("""
        OpenDisplay CLI
          --list                    List all displays
          --display N               Select display by index (default: 0)
          --brightness N            Set brightness (0-100)
          --contrast N              Set contrast (0-100)
          --volume N                Set volume (0-100)
          --input <source>          Set input (hdmi1, hdmi2, dp1, dp2, usbc, vga, dvi)
          --power <mode>            Set power (on, standby, off)
          --resolution WxH          Set resolution (e.g. 2560x1440)
          --modes                   List available modes
          --help                    Show this help
        """)
    }
}
