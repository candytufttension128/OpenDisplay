import AppKit
import CoreGraphics

/// Software gamma-based dimming and color temperature
class GammaDimmer {
    /// Dim display via gamma. factor: 0.0 (black) to 1.0 (normal)
    func setDimming(factor: CGFloat, for displayID: CGDirectDisplayID) {
        let f = Float(max(0, min(1, factor)))
        var r = [CGGammaValue](repeating: 0, count: 256)
        var g = [CGGammaValue](repeating: 0, count: 256)
        var b = [CGGammaValue](repeating: 0, count: 256)
        for i in 0..<256 { let v = Float(i) / 255.0; r[i] = v * f; g[i] = v * f; b[i] = v * f }
        CGSetDisplayTransferByTable(displayID, 256, &r, &g, &b)
    }

    /// Color temperature via gamma. kelvin: 1000 (warm) to 10000 (cool)
    func setColorTemperature(_ kelvin: Int, brightness: CGFloat = 1.0, for displayID: CGDirectDisplayID) {
        let (rm, gm, bm) = kelvinToRGB(kelvin)
        let f = Float(max(0, min(1, brightness)))
        var r = [CGGammaValue](repeating: 0, count: 256)
        var g = [CGGammaValue](repeating: 0, count: 256)
        var b = [CGGammaValue](repeating: 0, count: 256)
        for i in 0..<256 { let v = Float(i) / 255.0; r[i] = v * rm * f; g[i] = v * gm * f; b[i] = v * bm * f }
        CGSetDisplayTransferByTable(displayID, 256, &r, &g, &b)
    }

    func resetGamma(for displayID: CGDirectDisplayID) { CGDisplayRestoreColorSyncSettings() }
    func resetAll() { CGDisplayRestoreColorSyncSettings() }

    /// Tanner Helland algorithm
    private func kelvinToRGB(_ kelvin: Int) -> (Float, Float, Float) {
        let t = Float(max(1000, min(40000, kelvin))) / 100.0
        let r: Float, g: Float, b: Float
        if t <= 66 {
            r = 1.0; g = max(0, min(1, (99.4708 * log(t) - 161.1196) / 255.0))
        } else {
            r = max(0, min(1, (329.6987 * pow(t - 60, -0.1332)) / 255.0))
            g = max(0, min(1, (288.1222 * pow(t - 60, -0.0755)) / 255.0))
        }
        if t >= 66 { b = 1.0 }
        else if t <= 19 { b = 0.0 }
        else { b = max(0, min(1, (138.5177 * log(t - 10) - 305.0448) / 255.0)) }
        return (r, g, b)
    }
}
