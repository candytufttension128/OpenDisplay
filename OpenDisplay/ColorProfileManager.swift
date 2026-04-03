import AppKit
import CoreGraphics

/// Color profile management
struct ColorProfileManager {
    static func installedProfiles() -> [String] {
        let dirs = [
            URL(fileURLWithPath: "/Library/ColorSync/Profiles"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/ColorSync/Profiles")
        ]
        var names: [String] = []
        for dir in dirs {
            if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                names += files.filter { $0.pathExtension == "icc" || $0.pathExtension == "icm" }
                    .map { $0.deletingPathExtension().lastPathComponent }
            }
        }
        return names.sorted()
    }

    static func currentProfile(for displayID: CGDirectDisplayID) -> String? {
        let space = CGDisplayCopyColorSpace(displayID)
        return space.name as String?
    }
}
