import Foundation

/// Persistent settings and display profiles
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    struct DisplayProfile: Codable, Identifiable {
        var id: String { name }
        var name: String
        var brightness: Double?
        var contrast: Double?
        var volume: Double?
        var resolutionModeID: Int32?
        var colorTempKelvin: Int?
        var softwareDimming: Double?
        var overlayDimming: Double?
        var customName: String?
    }

    @Published var profiles: [DisplayProfile] = []
    @Published var launchAtLogin: Bool {
        didSet { setLaunchAtLogin(launchAtLogin) }
    }

    private let profilesKey = "OpenDisplay.profiles"
    private let launchKey = "OpenDisplay.launchAtLogin"

    init() {
        launchAtLogin = UserDefaults.standard.bool(forKey: launchKey)
        loadProfiles()
    }

    func saveProfile(_ profile: DisplayProfile) {
        if let idx = profiles.firstIndex(where: { $0.name == profile.name }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        persistProfiles()
    }

    func deleteProfile(named name: String) {
        profiles.removeAll { $0.name == name }
        persistProfiles()
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: profilesKey),
              let decoded = try? JSONDecoder().decode([DisplayProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: launchKey)
        // SMAppService requires macOS 13+ and a proper bundle; use SMLoginItemSetEnabled for now
        // In a real app bundle, use: SMAppService.mainApp.register() / unregister()
    }
}
