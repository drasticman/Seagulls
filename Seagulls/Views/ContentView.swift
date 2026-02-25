//
//  ContentView.swift
//  Seagulls
//
//  Updated 2/18/26 — proper post-setup re-evaluation
//

import SwiftUI
import AppKit

struct ContentView: View {

    @State private var desktopCDLURL: URL?
    @State private var archiveRootURL: URL?
    @State private var volumeURL: URL?
    @State private var showingSetup = false
    @State private var statusMessage = "Ready"
    @State private var settingsLoaded = false
    @State private var loadedSettings: CDLSettings?
    @State private var volumeWatcherTask: Task<Void, Never>?
    @State private var workflowTask: Task<Void, Never>?
    @State private var isRunning = false
    @State private var escapeMonitor: Any?
    @State private var untrustedDrives: [MountedDrive] = []
    @State private var attemptedStreamDeckInstallPrompt = false

    @StateObject private var driveRegistry = DriveRegistryModel.shared
    @StateObject private var bridge = StreamDeckBridge.shared

    var body: some View {
        VStack(spacing: 20) {

            if settingsLoaded {
                VStack(spacing: 20) {

                    if let desktop = desktopCDLURL {
                        Text("CDL Folder: \(desktop.path)")
                    }

                    if let archive = archiveRootURL {
                        Text("Framegrab Archive Folder: \(archive.path)")
                    }

                    if let volume = volumeURL {
                        Text("Thumb Drive Volume: \(volume.path)")
                            .transition(.opacity)
                    } else {
                        VStack {
                            Text("Thumb Drive Volume: Not mounted")
                                .foregroundColor(.secondary)

                            ForEach(untrustedDrives, id: \.url) { drive in
                                HStack {
                                    Text("Untrusted: \(drive.volumeName ?? "Unknown")")
                                        .foregroundColor(.orange)
                                    Button("Trust") {
                                        trustDrive(drive)
                                    }
                                }
                            }
                        }
                    }

                    Button("Change Settings") {
                        showingSetup = true
                    }

                    Divider()

                    Button("Start Workflow") {
                        startWorkflow()
                    }
                    .disabled(volumeURL == nil || isRunning)
                    .keyboardShortcut(.defaultAction)
                }

            } else {
                Text("No settings found.")
                Button("Setup Folders") {
                    showingSetup = true
                }
            }

            Divider()

            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Status: \(statusMessage)")
                    .foregroundColor(.gray)
                    .animation(.easeInOut(duration: 0.2), value: statusMessage)
            }

            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            Text("Seagulls v\(appVersion) (Build \(buildNumber))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)

        .onAppear {
            logAllMountedVolumes()
            loadSettings()
            evaluateSetupCompletion()
            bridge.updateCachedStatusJSON()

            triggerStreamDeckInstallPromptIfNeeded()

            if !settingsLoaded {
                showingSetup = true
            }

            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 {
                    if isRunning {
                        cancelWorkflow(activate: false)
                        return nil
                    }
                }
                return event
            }
        }

        .onDisappear {
            volumeWatcherTask?.cancel()

            if let monitor = escapeMonitor {
                NSEvent.removeMonitor(monitor)
                escapeMonitor = nil
            }
        }

        .onChange(of: showingSetup) { _, isShowing in
            if !isShowing {
                loadSettings()
                evaluateSetupCompletion()
                triggerStreamDeckInstallPromptIfNeeded()
            }
        }

        .onChange(of: statusMessage) { _, newValue in
            bridge.statusMessage = newValue
            bridge.updateCachedStatusJSON()
        }
        .onChange(of: isRunning) { _, newValue in
            bridge.isRunning = newValue
            bridge.updateCachedStatusJSON()
        }

        // Stream Deck events
        .onReceive(NotificationCenter.default.publisher(for: .sdOpenSettings)) { _ in
            showingSetup = true
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdStartWorkflow)) { _ in
            startWorkflow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdCancelWorkflow)) { _ in
            cancelWorkflow(activate: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdShowMain)) { _ in
            showingSetup = false
            NSApp.activate(ignoringOtherApps: true)
        }

        // Escape cancels while running
        .onExitCommand {
            if isRunning {
                cancelWorkflow(activate: false)
            }
        }

        // Trust actions
        .onReceive(NotificationCenter.default.publisher(for: .sdTrustFirstUntrusted)) { _ in
            if let first = untrustedDrives.first {
                trustDrive(first)
            } else {
                statusMessage = "No untrusted drive to trust"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdTrustByName)) { note in
            guard let name = note.userInfo?["name"] as? String else { return }
            if let match = untrustedDrives.first(where: { ($0.volumeName ?? "") == name }) {
                trustDrive(match)
            } else {
                statusMessage = "Untrusted drive '\(name)' not found"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sdTrustByUUID)) { note in
            guard let uuidString = note.userInfo?["uuid"] as? String,
                  let uuid = UUID(uuidString: uuidString) else { return }

            if let match = untrustedDrives.first(where: { $0.volumeUUID == uuid }) {
                trustDrive(match)
            } else {
                statusMessage = "Untrusted drive UUID not found"
            }
        }

        .sheet(isPresented: $showingSetup) {
            SetupView(
                desktopCDLURL: $desktopCDLURL,
                archiveRootURL: $archiveRootURL,
                volumeURL: $volumeURL,
                statusMessage: $statusMessage
            )
        }
    }

    // MARK: - Settings

    private func triggerStreamDeckInstallPromptIfNeeded() {
        guard !attemptedStreamDeckInstallPrompt else { return }
        guard !showingSetup else { return }

        attemptedStreamDeckInstallPrompt = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            StreamDeckInstaller.shared.promptForInstallOrUpdateIfNeeded()
        }
    }

    func loadSettings() {
        guard let settings = CDLSettingsStore.load() else {
            volumeWatcherTask?.cancel()
            settingsLoaded = false
            loadedSettings = nil
            desktopCDLURL = nil
            archiveRootURL = nil
            volumeURL = nil
            untrustedDrives = []
            return
        }

        loadedSettings = settings
        settingsLoaded = true

        desktopCDLURL = settings.desktopCDLURL
        archiveRootURL = settings.archiveRootURL
        volumeURL = settings.volumeURL

        startVolumeWatcher()
    }

    private func evaluateSetupCompletion() {
        if desktopCDLURL != nil && archiveRootURL != nil {
            statusMessage = volumeURL == nil
            ? "Settings loaded — waiting for thumb drive"
            : "Settings loaded"
        } else {
            statusMessage = "No settings found — please set up folders"
        }
    }

    // MARK: - Volume watcher

    func startVolumeWatcher() {
        volumeWatcherTask?.cancel()

        refreshMountedDrives()

        volumeWatcherTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    refreshMountedDrives()
                }
            }
        }
    }

    @MainActor
    func refreshMountedDrives() {
        let mounted = mountedRemovableDrives()
        let candidates = candidateDrives(from: mounted).map { $0.mountedDrive }

        // Partition once for clarity
        let trustedCandidates = candidates.filter { driveRegistry.isTrusted($0) }
        let untrustedCandidates = candidates.filter { !driveRegistry.isTrusted($0) }

        // Always keep untrustedDrives up to date for UI + /status
        untrustedDrives = untrustedCandidates

        bridge.untrustedDrives = untrustedDrives.map { d in
            StreamDeckBridge.DriveInfo(
                uuid: d.volumeUUID?.uuidString,
                name: d.volumeName,
                capacityBytes: d.capacityBytes
            )
        }

        // --- Trusted drive policy ---
        if trustedCandidates.count > 1 {
            // Multiple trusted drives: refuse to pick. Require user to eject/untrust one.
            if volumeURL != nil {
                withAnimation(.easeInOut(duration: 0.2)) {
                    volumeURL = nil
                }
            }

            statusMessage = "Multiple trusted drives detected — eject one"

            bridge.driveState = .trustedMultiple
            bridge.trustedVolumeName = nil
            bridge.updateCachedStatusJSON()
            return
        }

        if let trustedDrive = trustedCandidates.first {
            // Exactly one trusted drive
            if volumeURL != trustedDrive.url {
                withAnimation(.easeInOut(duration: 0.2)) {
                    volumeURL = trustedDrive.url
                }
                statusMessage = "\(trustedDrive.volumeName ?? "Thumb drive") detected — ready to start"
            }

            bridge.driveState = .trustedPresent
            bridge.trustedVolumeName = trustedDrive.volumeName ?? trustedDrive.url.lastPathComponent
            bridge.updateCachedStatusJSON()
            return
        }

        // No trusted drive
        if volumeURL != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                volumeURL = nil
            }
            statusMessage = "Trusted thumb drive disconnected"
        }

        if !untrustedDrives.isEmpty {
            bridge.driveState = .untrustedPresent
            bridge.trustedVolumeName = nil
        } else {
            bridge.driveState = .noDrive
            bridge.trustedVolumeName = nil
        }

        bridge.updateCachedStatusJSON()
    }

    @MainActor
    func trustDrive(_ drive: MountedDrive) {
        driveRegistry.add(drive)
        volumeURL = drive.url
        statusMessage = "\(drive.volumeName ?? "Thumb drive") trusted — ready to start"
    }

    // MARK: - Main Workflow

    func startWorkflow() {
        guard !isRunning else { return }
        isRunning = true

        guard let desktop = desktopCDLURL,
              let archiveRoot = archiveRootURL,
              let volume = volumeURL else {
            isRunning = false
            return
        }

        workflowTask?.cancel()
        workflowTask = Task {
            await runWorkflow(desktop: desktop, archiveRoot: archiveRoot, volume: volume)
        }
    }

    @MainActor
    private func runWorkflow(desktop: URL, archiveRoot: URL, volume: URL) async {
        defer {
            isRunning = false
            workflowTask = nil
        }

        do {
            try Task.checkCancellation()

            let shootingDay = await PromptBroker.shared.requestShootingDay()
            guard !shootingDay.isEmpty else {
                statusMessage = "Workflow cancelled"
                return
            }

            try Task.checkCancellation()

            let breakName = await PromptBroker.shared.requestBreakName()
            guard !breakName.isEmpty else {
                statusMessage = "Workflow cancelled"
                return
            }

            try Task.checkCancellation()

            statusMessage = "Waiting for files in CDL folder…"
            try await waitForFiles(in: desktop)

            try Task.checkCancellation()

            statusMessage = "Waiting for thumb drive…"
            try await waitForDrive(at: volume)

            try Task.checkCancellation()

            let visible = meaningfulContents(of: volume)
            if !visible.isEmpty {
                statusMessage = "Thumb drive not empty — awaiting wipe / skip / cancel"

                let choice = await PromptBroker.shared.requestWipeChoice(
                    volumeURL: volume,
                    volumeName: volume.lastPathComponent
                )

                switch choice {
                case .wipe:
                    statusMessage = "Wiping thumb drive…"
                    try? removeContents(of: volume)

                case .skip:
                    statusMessage = "Continuing without wipe…"

                case .cancel:
                    statusMessage = "Workflow cancelled"
                    return
                }
            }

            try Task.checkCancellation()

            let volumeTarget = volume.appendingPathComponent(
                "Day \(shootingDay) \(breakName) CDLs and Framegrabs",
                isDirectory: true
            )

            try? FileManager.default.createDirectory(at: volumeTarget, withIntermediateDirectories: true)
            try? copyContents(from: desktop, to: volumeTarget)
            deleteCDLFiles(in: desktop)

            let archiveDay = archiveRoot.appendingPathComponent("Day \(shootingDay)", isDirectory: true)
            try? FileManager.default.createDirectory(at: archiveDay, withIntermediateDirectories: true)
            try? moveContents(from: desktop, to: archiveDay)

            NSWorkspace.shared.open(volumeTarget)
            if let firstJPG = firstFile(withExtensions: ["jpg", "jpeg"], in: volumeTarget) {
                NSWorkspace.shared.open(firstJPG)
            }

            statusMessage = "Workflow complete!"

        } catch is CancellationError {
            statusMessage = "Workflow cancelled"
        } catch {
            statusMessage = "Workflow failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    func cancelWorkflow(activate: Bool) {
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }

        workflowTask?.cancel()
        PromptBroker.shared.cancelPendingPromptIfAny()

        if isRunning {
            statusMessage = "Workflow cancelled"
        }
    }

    // MARK: - Waiting helpers

    func waitForFiles(in folder: URL) async throws {
        let fm = FileManager.default
        var lastSnapshot: (cdlCount: Int, jpgCount: Int, size: Int64) = (0, 0, 0)
        var stableSeconds = 0
        let requiredStableSeconds = 3

        while true {
            try Task.checkCancellation()

            guard let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    statusMessage = "Waiting for files… (cannot read folder)"
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let cdls = items.filter { $0.pathExtension.lowercased() == "cdl" }
            let jpgs = items.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            let deliverables = cdls + jpgs

            await MainActor.run {
                if deliverables.isEmpty {
                    statusMessage = "Waiting for files… (CDLs: 0, JPGs: 0)"
                } else {
                    statusMessage = "Waiting for files… (CDLs: \(cdls.count), JPGs: \(jpgs.count))"
                }
            }

            if deliverables.isEmpty {
                stableSeconds = 0
                lastSnapshot = (0, 0, 0)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let size = deliverables.reduce(Int64(0)) { total, url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                return total + Int64(values?.fileSize ?? 0)
            }

            let currentSnapshot = (cdlCount: cdls.count, jpgCount: jpgs.count, size: size)

            if currentSnapshot.cdlCount == lastSnapshot.cdlCount &&
                currentSnapshot.jpgCount == lastSnapshot.jpgCount &&
                currentSnapshot.size == lastSnapshot.size {
                stableSeconds += 1
            } else {
                stableSeconds = 0
                lastSnapshot = currentSnapshot
            }

            await MainActor.run {
                statusMessage = "Waiting for files… (CDLs: \(cdls.count), JPGs: \(jpgs.count), stable \(stableSeconds)/\(requiredStableSeconds))"
            }

            if stableSeconds >= requiredStableSeconds {
                return
            }

            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func waitForDrive(at folder: URL) async throws {
        while !FileManager.default.fileExists(atPath: folder.path) {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

#Preview {
    ContentView()
}
