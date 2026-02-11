//
//  DriveRegistry.swift
//  Seagulls
//
//  Created by Andy Bader on 2/11/26.
//  Updated 2/11/26
//

import Foundation

class DriveRegistry {
    static let shared = DriveRegistry()
    
    private(set) var trustedDrives: [UUID: TrustedDrive] = [:]
    
    /// List of drive names that we currently consider "trusted".
    /// ✅ Right now only DIT_CDLs, but you can expand this in the future.
    private let allowedDriveNames: [String] = ["DIT_CDLs"]
    
    // MARK: - Register candidate drives
    func registerCandidate(_ drive: MountedDrive) {
        guard let uuid = drive.volumeUUID else { return }

        // Only allow drives with approved names
        if let name = drive.volumeName, !allowedDriveNames.contains(name) {
            print("Drive \(name) (\(uuid)) ignored — not in allowed list")
            return
        }

        // Only add if not already trusted
        if trustedDrives[uuid] == nil {
            let trusted = TrustedDrive(
                id: UUID(),              // app-internal id
                volumeUUID: uuid,
                volumeName: drive.volumeName,
                capacityBytes: drive.capacityBytes,
                addedAt: Date()
            )
            trustedDrives[uuid] = trusted
            print("Auto-trusted drive: \(trusted.volumeName ?? "Unknown") (\(uuid))")
        }
    }
    
    func allTrusted() -> [TrustedDrive] {
        Array(trustedDrives.values)
    }
}
