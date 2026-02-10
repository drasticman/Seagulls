//
//  MountedDriveDiscovery.swift
//  Seagulls
//
//  Created by Andy Bader on 2/10/26.
//

import Foundation

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
    ) else {
        return []
    }

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
