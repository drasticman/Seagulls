//
//  DriveIdentity.swift
//  Seagulls
//
//  Created by Andy Bader on 2/10/26.
//

import Foundation

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


