//
//  MountedDriveDiscovery.swift
//  Seagulls
//
//  Created by Andy Bader on 2/10/26.
//  Rewritten 2/11/26
//  Refactored 2/11/26 — no SwiftUI state references
//

import Foundation

// MARK: - Discover mounted removable drives

func mountedRemovableDrives() -> [MountedDrive] {
    let fm = FileManager.default

    guard let urls = fm.mountedVolumeURLs(
        includingResourceValuesForKeys: [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeIsRemovableKey
        ],
        options: []
    ) else { return [] }

    return urls.compactMap { url in
        let values = try? url.resourceValues(forKeys: [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeIsRemovableKey
        ])

        guard values?.volumeIsRemovable == true else { return nil }

        let volumeUUID = values?.volumeUUIDString.flatMap(UUID.init(uuidString:))
        let capacity = values?.volumeTotalCapacity.map(Int64.init)

        return MountedDrive(
            url: url,
            volumeUUID: volumeUUID,
            volumeName: values?.volumeName,
            capacityBytes: capacity,
            isRemovable: true
        )
    }
}

// MARK: - Log all mounted volumes for debugging

func logAllMountedVolumes() {
    let fm = FileManager.default

    let keys: Set<URLResourceKey> = [
        .volumeUUIDStringKey,
        .volumeNameKey,
        .volumeTotalCapacityKey,
        .volumeIsRemovableKey,
        .volumeIsInternalKey
    ]

    guard let urls = fm.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys),
        options: []
    ) else {
        print("No mounted volumes found")
        return
    }

    for url in urls {
        let values = try? url.resourceValues(forKeys: keys)

        print("""
        Mounted volume:
          name: \(values?.volumeName ?? "unknown")
          uuid: \(values?.volumeUUIDString ?? "unknown")
          path: \(url.path)
          capacity: \(values?.volumeTotalCapacity ?? 0)
          removable: \(values?.volumeIsRemovable ?? false)
          internal: \(values?.volumeIsInternal ?? false)
        """)
    }
}

// MARK: - Determine candidate drives

func candidateDrives(from mounted: [MountedDrive]) -> [CandidateDrive] {
    let filtered = mounted.filter { drive in
        guard drive.isRemovable else { return false }
        let path = drive.url.path
        return !path.contains("CoreSimulator") && !path.contains("Time Machine")
    }

    if filtered.isEmpty {
        print("No candidate drives found")
    } else {
        for drive in filtered {
            print("Candidate drive: \(drive.volumeName ?? "unknown") — Removable & sane path")
        }
    }

    return filtered.map { CandidateDrive(mountedDrive: $0, reason: "Removable & sane path") }
}

// MARK: - Auto-trust allowed drives

func autoTrustAllowedDrives(from drives: [MountedDrive]) {
    for drive in drives {
        if drive.volumeName == "DIT_CDLs" {
            DriveRegistry.shared.registerCandidate(drive)
            #if DEBUG
            print("Auto-trusted drive: \(drive.volumeName ?? "unknown") — \(drive.url.path)")
            #endif
        }
    }
}
