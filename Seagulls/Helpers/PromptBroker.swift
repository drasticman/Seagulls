//
//  PromptBroker.swift
//  Seagulls
//
//  Created by Andy Bader on 2/23/26.
//

import Foundation
import AppKit
import os

/// A tiny broker that lets prompts be answered either:
/// - locally (NSAlert like today)
/// - or remotely via an API call (Stream Deck / curl)
///
/// Safe & reversible: if nobody answers remotely, it behaves like before.
final class PromptBroker: @unchecked Sendable {
    static let shared = PromptBroker()

    private init() {}

    enum PromptID: String {
        case shootingDay
        case breakName
        case wipeChoice
    }

    enum RemoteValue {
        case text(String)
        case wipe(WipeChoice)
        case cancel
    }

    private enum Winner<T> {
        case local(T)
        case remote(RemoteValue)
    }

    private struct PromptHandle {
        let gen: Int
        let token: String
    }

    private struct PendingState {
        var promptGeneration: Int = 0
        var pendingID: PromptID?
        var pendingToken: String?
        var pendingContinuation: CheckedContinuation<RemoteValue, Never>?
    }

    // ✅ Swift 6-safe: the lock owns the state (no separate `state` property).
    private let stateLock = OSAllocatedUnfairLock<PendingState>(initialState: PendingState())

    // MARK: - Public prompt entry points used by workflow

    func requestShootingDay() async -> String {
        await requestText(
            id: .shootingDay,
            title: "Shooting Day",
            message: "Enter the shooting day (e.g. 6):"
        )
    }

    func requestBreakName() async -> String {
        await requestBreak(
            id: .breakName,
            title: "Break / AM-PM",
            message: "Select or type a break designation:"
        )
    }

    func requestWipeChoice(volumeURL: URL, volumeName: String) async -> WipeChoice {
        await requestWipe(
            id: .wipeChoice,
            title: "Thumb Drive Not Empty",
            message: "Files already exist on this drive. Do you want to wipe it, continue without wiping, or cancel the workflow?",
            volumeURL: volumeURL,
            volumeName: volumeName
        )
    }

    // MARK: - Remote answer (called by HTTP server)

    func submitRemoteAnswer(promptToken: String, promptID: String, value: String) -> Bool {
        guard let id = PromptID(rawValue: promptID) else { print("🟥 bad kind"); return false }

        let matches = stateLock.withLock { st in
            (st.pendingID == id && st.pendingToken == promptToken)
        }

        print("🟦 submitRemoteAnswer kind=\(promptID) token=\(promptToken) value=\(value) matches=\(matches)")

        guard matches else { return false }

        switch id {
        case .shootingDay, .breakName:
            resolveRemote(.text(value))
            return true

        case .wipeChoice:
            let v = value.lowercased()
            if v == "wipe" { resolveRemote(.wipe(.wipe)); return true }
            if v == "skip" { resolveRemote(.wipe(.skip)); return true }
            if v == "cancel" { resolveRemote(.wipe(.cancel)); return true }
            print("🟥 invalid wipe value")
            return false
        }
    }

    func submitRemoteCancel(promptToken: String, promptID: String) -> Bool {
        guard let id = PromptID(rawValue: promptID) else { return false }

        let matches = stateLock.withLock { st in
            (st.pendingID == id && st.pendingToken == promptToken)
        }

        guard matches else { return false }
        resolveRemote(.cancel)
        return true
    }

    // MARK: - Core prompt plumbing

    @discardableResult
    private func beginPrompt(id: PromptID, title: String, message: String, options: [String]) -> PromptHandle {
        let handle: PromptHandle = stateLock.withLock { st in
            st.promptGeneration += 1
            let gen = st.promptGeneration
            let token = UUID().uuidString
            st.pendingID = id
            st.pendingToken = token
            return PromptHandle(gen: gen, token: token)
        }

        // Publish prompt details on MainActor
        Task { @MainActor in
            StreamDeckBridge.shared.pendingPromptID = id.rawValue
            StreamDeckBridge.shared.pendingPromptToken = handle.token
            StreamDeckBridge.shared.pendingPromptTitle = title
            StreamDeckBridge.shared.pendingPromptMessage = message
            StreamDeckBridge.shared.pendingPromptOptions = options
            StreamDeckBridge.shared.updateCachedStatusJSON()
        }

        return handle
    }

    private func endPrompt(gen: Int) {
        let shouldEnd: Bool = stateLock.withLock { st in
            guard gen == st.promptGeneration else { return false }
            st.pendingID = nil
            st.pendingToken = nil
            st.pendingContinuation = nil
            return true
        }
        guard shouldEnd else { return }

        Task { @MainActor in
            StreamDeckBridge.shared.pendingPromptID = nil
            StreamDeckBridge.shared.pendingPromptToken = nil
            StreamDeckBridge.shared.pendingPromptTitle = nil
            StreamDeckBridge.shared.pendingPromptMessage = nil
            StreamDeckBridge.shared.pendingPromptOptions = []
            StreamDeckBridge.shared.updateCachedStatusJSON()
        }
    }

    private func resolveRemote(_ value: RemoteValue) {
        let cont: CheckedContinuation<RemoteValue, Never>? = stateLock.withLock { st in
            let c = st.pendingContinuation
            st.pendingContinuation = nil
            return c
        }

        if cont == nil {
            print("🟥 resolveRemote called but pendingContinuation is nil")
        } else {
            print("🟩 resolveRemote resuming continuation")
        }

        cont?.resume(returning: value)
    }

    private func waitForRemote(id: PromptID) async -> RemoteValue {
        await withCheckedContinuation { cont in
            stateLock.withLock { st in
                st.pendingContinuation = cont
            }
        }
    }

    private func race<T>(
        id: PromptID,
        local: @escaping @MainActor () async -> T
    ) async -> Winner<T> {
        await withCheckedContinuation { cont in
            var finished = false

            func finish(_ result: Winner<T>) {
                guard !finished else { return }
                finished = true
                cont.resume(returning: result)
            }

            Task { @MainActor in
                let v = await local()
                finish(.local(v))
            }

            Task {
                let r = await self.waitForRemote(id: id)
                finish(.remote(r))
            }
        }
    }

    // MARK: - Prompt entrypoints used internally

    private func requestText(id: PromptID, title: String, message: String) async -> String {
        let handle = beginPrompt(id: id, title: title, message: message, options: ["OK", "Cancel"])

        let winner = await race(id: id) {
            await askText(title: title, message: message)
        }

        switch winner {
        case .remote(let r):
            await MainActor.run { self.dismissActivePromptSheetIfPresent() }
            endPrompt(gen: handle.gen)
            switch r {
            case .text(let s): return s
            default: return ""
            }

        case .local(let localValue):
            resolveRemote(.cancel)
            endPrompt(gen: handle.gen)
            return localValue
        }
    }

    private func requestBreak(id: PromptID, title: String, message: String) async -> String {
        let handle = beginPrompt(id: id, title: title, message: message, options: ["AM", "PM", "All Day", "Other", "Cancel"])

        let winner = await race(id: id) {
            await askBreak()
        }

        switch winner {
        case .remote(let r):
            await MainActor.run { self.dismissActivePromptSheetIfPresent() }
            endPrompt(gen: handle.gen)
            switch r {
            case .text(let s): return s
            default: return ""
            }

        case .local(let localValue):
            resolveRemote(.cancel)
            endPrompt(gen: handle.gen)
            return localValue
        }
    }

    @MainActor
    private func requestWipe(
        id: PromptID,
        title: String,
        message: String,
        volumeURL: URL,
        volumeName: String
    ) async -> WipeChoice {

        let handle = beginPrompt(
            id: id,
            title: title,
            message: "\(message)\n\nDrive: \(volumeName)",
            options: ["wipe", "skip", "cancel"]
        )

        // Remote wait begins immediately.
        let remoteTask = Task { await self.waitForRemote(id: id) }

        // Local UI begins after a short grace window (remote-first),
        // and will not show if remote has already resolved.
        let localTask = Task { @MainActor () -> WipeChoice in
            try? await Task.sleep(nanoseconds: 350_000_000)

            let stillPending: Bool = self.stateLock.withLock { st in
                (st.promptGeneration == handle.gen &&
                 st.pendingID == id &&
                 st.pendingToken != nil &&
                 st.pendingContinuation != nil)
            }

            guard stillPending else { return .cancel }
            return await confirmWipe(for: volumeURL)
        }

        // Race them.
        let winner: Winner<WipeChoice> = await withCheckedContinuation { cont in
            var finished = false
            func finish(_ w: Winner<WipeChoice>) {
                guard !finished else { return }
                finished = true
                cont.resume(returning: w)
            }

            Task { @MainActor in
                let v = await localTask.value
                finish(.local(v))
            }

            Task {
                let r = await remoteTask.value
                finish(.remote(r))
            }
        }

        switch winner {
        case .remote(let r):
            dismissActivePromptSheetIfPresent()
            endPrompt(gen: handle.gen)
            switch r {
            case .wipe(let w): return w
            case .cancel: return .cancel
            case .text: return .cancel
            }

        case .local(let localValue):
            resolveRemote(.cancel)
            endPrompt(gen: handle.gen)
            return localValue
        }
    }

    @MainActor
    private func dismissActivePromptSheetIfPresent() {
        if let sheet = seagullsActivePromptSheet, let parent = sheet.sheetParent {
            parent.endSheet(sheet)
            seagullsActivePromptSheet = nil
        }
    }
}
