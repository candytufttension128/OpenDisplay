import Foundation
import IOKit

/// Reads the MacBook ambient light sensor and syncs external monitor brightness
class AmbientLightSync: ObservableObject {
    @Published var enabled = false
    @Published var sensorValue: Double = 0
    @Published var minBrightness: Double = 5
    @Published var maxBrightness: Double = 100
    @Published var sensitivity: Double = 1.0 // multiplier

    private var timer: Timer?
    private var targetDisplays: [UInt32] = []
    private var lastSetBrightness: Double = -1

    func start(displays: [UInt32]) {
        targetDisplays = displays; enabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        enabled = false; timer?.invalidate(); timer = nil
    }

    private func poll() {
        guard let lux = readALS() else { return }
        sensorValue = lux
        let brightness = mapLuxToBrightness(lux)
        // Only update if changed by more than 2% to avoid flicker
        guard abs(brightness - lastSetBrightness) > 2 else { return }
        lastSetBrightness = brightness
        for id in targetDisplays {
            smoothSet(brightness: brightness, for: id)
        }
    }

    private func smoothSet(brightness target: Double, for displayID: UInt32) {
        guard let current = DDCControl.read(command: .brightness, for: displayID) else { return }
        let cur = Double(current.current)
        let steps = 5
        let delta = (target - cur) / Double(steps)
        for step in 1...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.05) {
                DDCControl.write(command: .brightness, value: UInt16(max(0, min(100, cur + delta * Double(step)))), for: displayID)
            }
        }
    }

    private func mapLuxToBrightness(_ lux: Double) -> Double {
        // Logarithmic mapping: dark room (~0 lux) → min, bright office (~500 lux) → max
        let normalized = log10(max(1, lux * sensitivity)) / log10(500)
        let clamped = max(0, min(1, normalized))
        return minBrightness + clamped * (maxBrightness - minBrightness)
    }

    /// Read ambient light sensor via IOKit
    private func readALS() -> Double? {
        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("AppleLMUController")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        let service = IOIteratorNext(iter)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connect) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connect) }

        var outputCount: UInt32 = 2
        var values = [UInt64](repeating: 0, count: 2)
        let result = IOConnectCallMethod(connect, 0, nil, 0, nil, 0, &values, &outputCount, nil, nil)
        guard result == KERN_SUCCESS else { return nil }

        // values[0] and values[1] are left and right sensor readings
        return Double(values[0] + values[1]) / 2.0
    }
}
