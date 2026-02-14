//
//  Settings.swift
//  Seagulls
//
//  Created by Andy Bader on 2/4/26.
//

import Foundation

struct CDLSettings: Codable {
    // Bookmarks for sandboxed access
    var desktopCDLBookmark: Data
    var archiveRootBookmark: Data
    var volumeBookmark: Data

    // MARK: - Helper methods to resolve URLs from bookmarks
    func desktopCDLURL() -> URL? {
        try? url(from: desktopCDLBookmark)
    }

    func archiveRootURL() -> URL? {
        try? url(from: archiveRootBookmark)
    }

    func volumeURL() -> URL? {
        try? url(from: volumeBookmark)
    }

    // MARK: - Display descriptions (for UI)
    var desktopCDLBookmarkDescription: String {
        desktopCDLURL()?.lastPathComponent ?? "Unknown"
    }

    var archiveRootBookmarkDescription: String {
        archiveRootURL()?.lastPathComponent ?? "Unknown"
    }

    var volumeBookmarkDescription: String {
        volumeURL()?.lastPathComponent ?? "Unknown"
    }

    // MARK: - Convenience initializer from URLs
    init(desktopURL: URL, archiveURL: URL, volumeURL: URL) throws {
        desktopCDLBookmark = try desktopURL.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil,
                                                          relativeTo: nil)
        archiveRootBookmark = try archiveURL.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil,
                                                          relativeTo: nil)
        self.volumeBookmark = try volumeURL.bookmarkData(options: .withSecurityScope,
                                                         includingResourceValuesForKeys: nil,
                                                         relativeTo: nil)
    }

    // MARK: - Helper to resolve a bookmark to a URL
    private func url(from bookmark: Data) throws -> URL {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark,
                          options: .withSecurityScope,
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        return url
    }
}

