import CoreGraphics
import Foundation

/// Scheduled night shift — adjusts color temperature based on time
class NightShiftScheduler: ObservableObject {
    @Published var enabled = false
    @Published var startHour = 20
    @Published var endHour = 7
    @Published var warmthKelvin = 3400 { didSet { if enabled { applyNow() } } }
    @Published var alwaysOn = false { didSet { if enabled { applyNow() } } }

    private var timer: Timer?
    private let dimmer = GammaDimmer()
    private var activeDisplays: [UInt32] = []

    func start(displays: [UInt32]) {
        activeDisplays = displays; enabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.evaluate() }
        applyNow()
    }

    func stop() {
        enabled = false; timer?.invalidate(); timer = nil; dimmer.resetAll()
    }

    func applyNow() {
        let shouldWarm = alwaysOn || isWithinSchedule()
        for id in activeDisplays {
            if shouldWarm { dimmer.setColorTemperature(warmthKelvin, for: id) }
            else { dimmer.resetGamma(for: id) }
        }
    }

    private func evaluate() { applyNow() }

    private func isWithinSchedule() -> Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= startHour || hour < endHour
    }
}
