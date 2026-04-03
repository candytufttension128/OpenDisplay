import Foundation

/// Export and import all app settings as JSON
struct SettingsExporter {
    struct ExportData: Codable {
        var profiles: [ProfileManager.DisplayProfile]
        var displayProfileMap: [String: String]
        var launchAtLogin: Bool
        var exportDate: Date
    }

    static func exportToJSON() -> Data? {
        let data = ExportData(
            profiles: ProfileManager.shared.profiles,
            displayProfileMap: [:], // DisplayEventWatcher mapping
            launchAtLogin: ProfileManager.shared.launchAtLogin,
            exportDate: Date()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(data)
    }

    static func exportToFile() -> URL? {
        guard let data = exportToJSON() else { return nil }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/OpenDisplay-settings.json")
        try? data.write(to: url)
        return url
    }

    static func importFromFile(url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return false }
        return importFromJSON(data)
    }

    static func importFromJSON(_ data: Data) -> Bool {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let imported = try? decoder.decode(ExportData.self, from: data) else { return false }
        for profile in imported.profiles {
            ProfileManager.shared.saveProfile(profile)
        }
        ProfileManager.shared.launchAtLogin = imported.launchAtLogin
        return true
    }
}
