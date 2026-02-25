//
//  StreamDeckBridge.swift
//  Seagulls
//
//  Created by Andy Bader on 2/18/26.
//

import Foundation
import Combine

@MainActor
final class StreamDeckBridge: ObservableObject {
    static let shared = StreamDeckBridge()

    // Prompt state (for /status + Stream Deck UI)
    @Published var pendingPromptID: String? = nil
    @Published var pendingPromptTitle: String? = nil
    @Published var pendingPromptMessage: String? = nil
    @Published var pendingPromptOptions: [String] = []
    @Published var pendingPromptToken: String?

    enum DriveState: String, Codable {
        case noDrive
        case untrustedPresent
        case trustedPresent
        case trustedMultiple
    }

    struct DriveInfo: Codable {
        let uuid: String?        // volume UUID string (if available)
        let name: String?
        let capacityBytes: Int64?
    }

    // Snapshot that an API can read
    @Published var statusMessage: String = "Ready"
    @Published var isRunning: Bool = false
    @Published var driveState: DriveState = .noDrive

    // Optional details (nice for Stream Deck UI)
    @Published var trustedVolumeName: String? = nil
    @Published var untrustedDrives: [DriveInfo] = []

    private init() {}

    // MARK: - Thread-safe status snapshot for LocalControlServer

    private let statusLock = NSLock()
    private var _cachedStatusJSON: Data = #"{"ok":false,"error":"status_not_ready"}"#.data(using: .utf8)!

    /// Call this on MainActor whenever any of the fields that appear in /status change.
    func updateCachedStatusJSON() {

        // ---- Derived fields for stable /status contract ----

        // Workflow state
        let workflowState: String
        if pendingPromptID != nil {
            workflowState = "awaitingInput"
        } else if isRunning {
            workflowState = "running"
        } else {
            workflowState = "idle"
        }

        // Drive count
        let driveCount: Int
        switch driveState {
        case .noDrive:
            driveCount = 0
        case .trustedPresent:
            driveCount = 1
        case .untrustedPresent:
            driveCount = untrustedDrives.count
        case .trustedMultiple:
            driveCount = 2
        }

        // ---- Minimal statusMessage tweak (untrusted drives) ----
        var statusForAPI = statusMessage
        if driveState == .untrustedPresent {
            if driveCount == 1, let name = untrustedDrives.first?.name, !name.isEmpty {
                statusForAPI = "Untrusted drive detected: \(name)"
            } else if driveCount > 1 {
                statusForAPI = "Multiple untrusted drives detected (\(driveCount))"
            } else {
                // Shouldn't happen, but keeps messaging sane if it does
                statusForAPI = "Untrusted drive detected"
            }
        }

        let payload: [String: Any] = [
            "ok": true,
            "apiVersion": 1,
            "workflowState": workflowState,

            // change only this line to use statusForAPI
            "statusMessage": statusForAPI,

            "isRunning": isRunning,
            "driveState": driveState.rawValue,
            "driveCount": driveCount,
            "trustedVolumeName": trustedVolumeName as Any,
            "pendingPrompt": (pendingPromptID == nil ? NSNull() : [
                "kind": pendingPromptID as Any,
                "token": pendingPromptToken as Any,
                "title": pendingPromptTitle as Any,
                "message": pendingPromptMessage as Any,
                "options": pendingPromptOptions
            ]),
            "untrustedDrives": untrustedDrives.map { di in
                [
                    "uuid": di.uuid as Any,
                    "name": di.name as Any,
                    "capacityBytes": di.capacityBytes as Any
                ]
            },
            "canStartWorkflow": (!isRunning && driveState == .trustedPresent)
        ]

        let data =
            (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]))
            ?? #"{"ok":false,"error":"status_encode_failed"}"#.data(using: .utf8)!

        statusLock.lock()
        _cachedStatusJSON = data
        statusLock.unlock()
    }

    /// Safe to call from any thread/queue.
    func cachedStatusJSON() -> Data {
        statusLock.lock()
        let data = _cachedStatusJSON
        statusLock.unlock()
        return data
    }
}
