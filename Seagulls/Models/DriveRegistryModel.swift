//
//  DriveRegistry.swift
//  Seagulls
//
//  Created by Andy Bader on 2/11/26.
//  Updated 2/11/26 — UUID-based only
//

import Foundation
import SwiftUI
import Combine

struct TrustedDrive: Codable, Identifiable {
    let id: UUID            // app-internal UUID
    let volumeUUID: UUID    // actual drive UUID
    let volumeName: String?
    let capacityBytes: Int64?
    let addedAt: Date
}

@MainActor
extension DriveRegistryModel {
    func untrust(_ drive: TrustedDrive) {
        trustedDrives.removeValue(forKey: drive.volumeUUID)
        saveToDisk()
    }

    func forgetAll() {
        trustedDrives.removeAll()
        saveToDisk()
    }
}

@MainActor
class DriveRegistryModel: ObservableObject {
    static let shared = DriveRegistryModel()
    
    @Published private(set) var trustedDrives: [UUID: TrustedDrive] = [:]  // keyed by volumeUUID
    
    private let storageURL: URL
    
    private init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Seagulls")
        
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        
        storageURL = appSupport.appendingPathComponent("drives.json")
        loadFromDisk()
    }
    
    // MARK: - Add / Trust a drive
    func add(_ drive: MountedDrive) {
        guard let uuid = drive.volumeUUID else { return }
        
        if trustedDrives[uuid] == nil {
            let trusted = TrustedDrive(
                id: UUID(),
                volumeUUID: uuid,
                volumeName: drive.volumeName,
                capacityBytes: drive.capacityBytes,
                addedAt: Date()
            )
            trustedDrives[uuid] = trusted
            print("✅ Trusted drive added: \(trusted.volumeName ?? "Unknown") (\(uuid))")
            saveToDisk()
        } else {
            print("ℹ️ Drive already trusted: \(drive.volumeName ?? "Unknown") (\(uuid))")
        }
    }
    
    // MARK: - Check if a drive is trusted
    func isTrusted(_ drive: MountedDrive) -> Bool {
        guard let uuid = drive.volumeUUID else { return false }
        return trustedDrives[uuid] != nil
    }
    
    // MARK: - Return all trusted drives
    func allTrusted() -> [TrustedDrive] {
        Array(trustedDrives.values)
    }
    
    // MARK: - JSON Persistence
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(trustedDrives)
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("⚠️ Failed to save trusted drives: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        if let decoded = try? JSONDecoder().decode([UUID: TrustedDrive].self, from: data) {
            trustedDrives = decoded
            print("📦 Loaded \(trustedDrives.count) trusted drive(s) from disk")
        }
    }
}


