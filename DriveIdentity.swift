//
//  DriveIdentity.swift
//  Seagulls
//
//  Created by Andy Bader on 2/10/26.
//

import Foundation

struct TrustedDrive: Codable, Identifiable, Equatable {
    let id: UUID                   // internal, app-level identity
    let volumeUUID: UUID?
    let volumeName: String?
    let capacityBytes: Int64?
    let addedAt: Date
}

struct MountedDrive {
    let url: URL
    let volumeUUID: UUID?
    let volumeName: String?
    let capacityBytes: Int64?
    let isRemovable: Bool
}
