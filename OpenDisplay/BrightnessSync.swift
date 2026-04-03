import AppKit
import CoreGraphics

/// Brightness sync — keeps multiple displays at the same brightness level
class BrightnessSync {
    private var timer: Timer?
    private var targetDisplays: [CGDirectDisplayID] = []
    private var sourceDisplay: CGDirectDisplayID = 0

    /// Start syncing brightness from source to targets, polling every interval seconds
    func start(source: CGDirectDisplayID, targets: [CGDirectDisplayID], interval: TimeInterval = 1.0) {
        stop()
        sourceDisplay = source; targetDisplays = targets
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sync()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func sync() {
        guard let srcVal = DDCControl.read(command: .brightness, for: sourceDisplay) else { return }
        for target in targetDisplays {
            // Read target's max to scale proportionally
            if let tgtVal = DDCControl.read(command: .brightness, for: target) {
                let scaled = UInt16(Double(srcVal.current) / Double(max(1, srcVal.max)) * Double(tgtVal.max))
                DDCControl.write(command: .brightness, value: scaled, for: target)
            }
        }
    }
}
