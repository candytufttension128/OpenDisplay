import CoreGraphics
import Foundation

/// Watches for display connect/disconnect events and auto-applies profiles
class DisplayEventWatcher: ObservableObject {
    @Published var autoProfileEnabled = false
    @Published var displayProfileMap: [String: String] = [:] // displayName → profileName

    private var lastKnownDisplays: Set<CGDirectDisplayID> = []
    var onDisplayConnected: ((CGDirectDisplayID) -> Void)?
    var onDisplayDisconnected: ((CGDirectDisplayID) -> Void)?

    func start() {
        autoProfileEnabled = true
        let mgr = DisplayManager()
        lastKnownDisplays = Set(mgr.displays.map(\.id))

        CGDisplayRegisterReconfigurationCallback({ displayID, flags, userInfo in
            let watcher = Unmanaged<DisplayEventWatcher>.fromOpaque(userInfo!).takeUnretainedValue()
            if flags.contains(.addFlag) {
                DispatchQueue.main.async { watcher.handleConnect(displayID) }
            }
            if flags.contains(.removeFlag) {
                DispatchQueue.main.async { watcher.handleDisconnect(displayID) }
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func stop() {
        autoProfileEnabled = false
        CGDisplayRemoveReconfigurationCallback({ _, _, userInfo in }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Map a display name to a profile name for auto-apply
    func setAutoProfile(displayName: String, profileName: String) {
        displayProfileMap[displayName] = profileName
        saveMapping()
    }

    private func handleConnect(_ displayID: CGDirectDisplayID) {
        lastKnownDisplays.insert(displayID)
        onDisplayConnected?(displayID)

        // Auto-apply profile
        let mgr = DisplayManager()
        guard let display = mgr.displays.first(where: { $0.id == displayID }),
              let profileName = displayProfileMap[display.name],
              let profile = ProfileManager.shared.profiles.first(where: { $0.name == profileName }) else { return }
        applyProfile(profile, to: displayID, manager: mgr)
    }

    private func handleDisconnect(_ displayID: CGDirectDisplayID) {
        lastKnownDisplays.remove(displayID)
        onDisplayDisconnected?(displayID)
    }

    private func applyProfile(_ profile: ProfileManager.DisplayProfile, to displayID: CGDirectDisplayID, manager: DisplayManager) {
        if let b = profile.brightness { DDCControl.write(command: .brightness, value: UInt16(b), for: displayID) }
        if let c = profile.contrast { DDCControl.write(command: .contrast, value: UInt16(c), for: displayID) }
        if let v = profile.volume { DDCControl.write(command: .volume, value: UInt16(v), for: displayID) }
        if let modeID = profile.resolutionModeID,
           let display = manager.displays.first(where: { $0.id == displayID }),
           let mode = manager.parsedModes(for: display).first(where: { $0.id == modeID }) {
            manager.setMode(mode, for: displayID)
        }
    }

    private let mappingKey = "OpenDisplay.displayProfileMap"
    private func saveMapping() {
        UserDefaults.standard.set(displayProfileMap, forKey: mappingKey)
    }
    func loadMapping() {
        displayProfileMap = (UserDefaults.standard.dictionary(forKey: mappingKey) as? [String: String]) ?? [:]
    }
}
