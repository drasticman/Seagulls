//
//  Settings.swift
//  Seagulls
//
//  Updated 2/18/26 — plain URL storage + migration from old bookmark settings
//

import Foundation

// MARK: - New settings format (plain URLs)
struct CDLSettings: Codable {
    var desktopCDLPath: String
    var archiveRootPath: String
    var volumePath: String

    var desktopCDLURL: URL { URL(fileURLWithPath: desktopCDLPath) }
    var archiveRootURL: URL { URL(fileURLWithPath: archiveRootPath) }
    var volumeURL: URL { URL(fileURLWithPath: volumePath) }

    init(desktopURL: URL, archiveURL: URL, volumeURL: URL) {
        self.desktopCDLPath = desktopURL.path
        self.archiveRootPath = archiveURL.path
        self.volumePath = volumeURL.path
    }
}

// MARK: - OLD settings format (bookmarks) for migration only
private struct LegacyCDLSettings: Codable {
    var desktopCDLBookmark: Data
    var archiveRootBookmark: Data
    var volumeBookmark: Data

    func desktopCDLURL() -> URL? { try? url(from: desktopCDLBookmark) }
    func archiveRootURL() -> URL? { try? url(from: archiveRootBookmark) }
    func volumeURL() -> URL? { try? url(from: volumeBookmark) }

    private func url(from bookmark: Data) throws -> URL {
        var isStale = false
        // Try both, because older writes used .withSecurityScope
        if let url = try? URL(resolvingBookmarkData: bookmark,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale) {
            return url
        }
        return try URL(resolvingBookmarkData: bookmark,
                       options: [],
                       relativeTo: nil,
                       bookmarkDataIsStale: &isStale)
    }
}

// MARK: - Load + migrate helper
enum CDLSettingsStore {

    static func settingsFileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Seagulls/settings.json")
    }

    static func load() -> CDLSettings? {
        let url = settingsFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }

        // 1) Try new plain format first
        if let decoded = try? JSONDecoder().decode(CDLSettings.self, from: data) {
            return decoded
        }

        // 2) Try legacy bookmark format and migrate
        if let legacy = try? JSONDecoder().decode(LegacyCDLSettings.self, from: data),
           let desktop = legacy.desktopCDLURL(),
           let archive = legacy.archiveRootURL(),
           let volume = legacy.volumeURL() {

            let migrated = CDLSettings(desktopURL: desktop, archiveURL: archive, volumeURL: volume)
            save(migrated) // overwrite file in new format
            return migrated
        }

        return nil
    }

    static func save(_ settings: CDLSettings) {
        let url = settingsFileURL()

        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}

// MARK: - Workflow autofill suggestions

struct WorkflowSuggestions: Codable, Equatable {
    var shootingDay: String
    var breakName: String

    static let initial = WorkflowSuggestions(
        shootingDay: "1",
        breakName: "AM"
    )

    func suggestionsAfterSuccessfulArchive(
        shootingDay completedShootingDay: String,
        breakName completedBreakName: String
    ) -> WorkflowSuggestions {
        let normalizedBreakName = completedBreakName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard normalizedBreakName == "am" ||
              normalizedBreakName == "pm" ||
              normalizedBreakName == "all day" else {
            return self
        }

        let normalizedShootingDay = completedShootingDay
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let shootingDayNumber = Int(normalizedShootingDay),
              shootingDayNumber > 0 else {
            return self
        }

        switch normalizedBreakName {
        case "am":
            return WorkflowSuggestions(
                shootingDay: String(shootingDayNumber),
                breakName: "PM"
            )

        case "pm", "all day":
            guard shootingDayNumber < Int.max else {
                return self
            }

            return WorkflowSuggestions(
                shootingDay: String(shootingDayNumber + 1),
                breakName: "AM"
            )

        default:
            return self
        }
    }
}
