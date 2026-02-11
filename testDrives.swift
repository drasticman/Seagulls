import Foundation

// MARK: - Models

struct MountedDrive {
    let url: URL
    let volumeUUID: UUID?
    let volumeName: String?
    let capacityBytes: Int64?
    let isRemovable: Bool
}

struct CandidateDrive {
    let mountedDrive: MountedDrive
    let reason: String
}

// MARK: - Registry

class DriveRegistry {
    static let shared = DriveRegistry()
    var trustedDrives: [UUID: MountedDrive] = [:]

    func registerCandidate(_ drive: MountedDrive) {
        guard let uuid = drive.volumeUUID else { return }
        trustedDrives[uuid] = drive
        print("Auto-trusted: \(drive.volumeName ?? "unknown")")
    }
}

// MARK: - Discovery

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
        return MountedDrive(
            url: url,
            volumeUUID: values?.volumeUUIDString.flatMap(UUID.init(uuidString:)),
            volumeName: values?.volumeName,
            capacityBytes: values?.volumeTotalCapacity.map(Int64.init),
            isRemovable: true
        )
    }
}

func candidateDrives(from mounted: [MountedDrive]) -> [CandidateDrive] {
    mounted.map { CandidateDrive(mountedDrive: $0, reason: "Removable") }
}

func autoTrustAllowedDrives(from candidates: [CandidateDrive]) {
    for c in candidates {
        if c.mountedDrive.volumeName == "DIT_CDLs" {
            DriveRegistry.shared.registerCandidate(c.mountedDrive)
        }
    }
}

// MARK: - Run

let drives = mountedRemovableDrives()
print("Detected removable drives:")
for d in drives {
    print("  \(d.volumeName ?? "unknown") — \(d.url.path) — uuid: \(d.volumeUUID?.uuidString ?? "nil")")
}

let candidates = candidateDrives(from: drives)
autoTrustAllowedDrives(from: candidates)

print("\nAll trusted drives:")
for (_, t) in DriveRegistry.shared.trustedDrives {
    print("  \(t.volumeName ?? "unknown") — \(t.volumeUUID?.uuidString ?? "nil")")
}

