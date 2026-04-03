import ServiceManagement
import Foundation

/// Proper launch-at-login using SMAppService (macOS 13+)
class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published var isEnabled: Bool {
        didSet { toggle(isEnabled) }
    }

    init() {
        // Default to enabled on first launch
        let hasLaunched = UserDefaults.standard.bool(forKey: "OpenDisplay.hasLaunchedBefore")
        if !hasLaunched {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "OpenDisplay.hasLaunchedBefore")
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func toggle(_ enable: Bool) {
        do {
            if enable { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Falls back silently — only works in a proper .app bundle
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
