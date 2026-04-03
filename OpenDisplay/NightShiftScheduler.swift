import CoreGraphics
import Foundation

/// Scheduled night shift — adjusts color temperature based on time
class NightShiftScheduler: ObservableObject {
    @Published var enabled = false
    @Published var startHour = 20
    @Published var endHour = 7
    @Published var warmthKelvin = 3400

    private var timer: Timer?
    private let dimmer = GammaDimmer()
    private var activeDisplays: [UInt32] = []

    func start(displays: [UInt32]) {
        activeDisplays = displays; enabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.evaluate() }
        evaluate()
    }

    func stop() {
        enabled = false; timer?.invalidate(); timer = nil; dimmer.resetAll()
    }

    private func evaluate() {
        let hour = Calendar.current.component(.hour, from: Date())
        let warm = hour >= startHour || hour < endHour
        for id in activeDisplays {
            if warm { dimmer.setColorTemperature(warmthKelvin, for: id) }
            else { dimmer.resetGamma(for: id) }
        }
    }
}
