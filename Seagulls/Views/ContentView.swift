//
//  ContentView.swift
//  Seagulls
//
//  Created by Andy Bader on 2/4/26
//  Updated 2/14/26 — mounted/untrusted drives moved out of body, smooth animations
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
    @State private var isRunning = false

    @State private var untrustedDrives: [MountedDrive] = []

    @StateObject private var driveRegistry = DriveRegistryModel.shared

    var body: some View {
        VStack(spacing: 20) {

            if settingsLoaded {
                VStack(spacing: 20) {

                    if let desktop = desktopCDLURL {
                        Text("Desktop CDL Folder: \(desktop.path)")
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
                                .transition(.opacity)
                                .foregroundColor(.secondary)

                            ForEach(untrustedDrives, id: \.url) { drive in
                                HStack {
                                    Text("Untrusted: \(drive.volumeName ?? "Unknown")")
                                        .foregroundColor(.orange)
                                    Button("Trust") {
                                        Task { @MainActor in
                                            trustDrive(drive)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Button("Change Settings") { showingSetup = true }

                    Divider()

                    Button("Start Workflow") {
                        startWorkflow()
                    }
                    .disabled(volumeURL == nil || isRunning)
                    .keyboardShortcut(.defaultAction)

                }

            } else {
                Text("No settings found.")
                Button("Setup Folders") { showingSetup = true }
            }

            Divider()

            // Status message
            HStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Status: \(statusMessage)")
                    .foregroundColor(.gray)
                    .animation(.easeInOut(duration: 0.2), value: statusMessage)
            }

            // --- Version footer ---
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            Text("Seagulls v\(appVersion) (Build \(buildNumber))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
        .onAppear {
            logAllMountedVolumes()        // DEBUG
            loadSettings()                // load saved settings
        }
        .onDisappear {
            volumeWatcherTask?.cancel()
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

    func loadSettings() {
        let url = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Seagulls/settings.json")

        guard
            let data = try? Data(contentsOf: url),
            let settings = try? JSONDecoder().decode(CDLSettings.self, from: data)
        else {
            Task { @MainActor in
                statusMessage = "No settings found — please set up folders"
                settingsLoaded = false
                loadedSettings = nil
            }
            return
        }

        loadedSettings = settings
        settingsLoaded = true

        desktopCDLURL = settings.desktopCDLURL()
        archiveRootURL = settings.archiveRootURL()
        volumeURL = settings.volumeURL()

        if let url = volumeURL,
           let uuid = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
            print("📌 Saved volume from settings:")
            print("   name: \(url.lastPathComponent)")
            print("   uuid: \(uuid)")
        } else {
            print("⚠️ Saved volume has no UUID or failed to resolve")
        }

        Task { @MainActor in
            if volumeURL == nil {
                statusMessage = "Settings loaded — waiting for thumb drive"
            } else {
                statusMessage = "Settings loaded"
            }
        }

        startVolumeWatcher()
    }

    // MARK: - Volume watcher

    func startVolumeWatcher() {
        volumeWatcherTask?.cancel()

        volumeWatcherTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshMountedDrives()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    @MainActor
    func refreshMountedDrives() {
        let mounted = mountedRemovableDrives()
        let candidates = candidateDrives(from: mounted).map { $0.mountedDrive }

        // Pick first trusted drive
        if let trustedDrive = candidates.first(where: { driveRegistry.isTrusted($0) }) {
            if volumeURL != trustedDrive.url {
                withAnimation(.easeInOut(duration: 0.2)) {
                    volumeURL = trustedDrive.url
                }
                statusMessage = "\(trustedDrive.volumeName ?? "Thumb drive") detected — ready to start"
                print("✅ Trusted drive selected: \(trustedDrive.volumeName ?? "unknown")")
            }
        } else if !driveRegistry.allTrusted().isEmpty, volumeURL == nil {
            // Pick first trusted drive even if it's not currently mounted
            let firstTrusted = driveRegistry.allTrusted().first!
            volumeURL = mounted.first(where: { $0.volumeUUID == firstTrusted.volumeUUID })?.url
            if volumeURL != nil {
                statusMessage = "\(firstTrusted.volumeName ?? "Thumb drive") detected — ready to start"
            } else {
                statusMessage = "Trusted thumb drive not mounted"
            }
        } else if volumeURL != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                volumeURL = nil
            }
            statusMessage = "Trusted thumb drive disconnected"
        }

        // Update untrusted drives list
        untrustedDrives = candidates.filter { !driveRegistry.isTrusted($0) }
    }


    // MARK: - Trusting a drive

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

        Task { @MainActor in
            defer { isRunning = false }

            // 1️⃣ Shooting day
            let shootingDay = await askText(title: "Shooting Day", message: "Enter the shooting day (e.g. 6):")
            guard !shootingDay.isEmpty else {
                statusMessage = "Workflow cancelled"
                return
            }

            // 2️⃣ Break
            let breakName = await askBreak()
            guard !breakName.isEmpty else {
                statusMessage = "Workflow cancelled"
                return
            }

            // 3️⃣ Wait for CDL/JPGs
            statusMessage = "Waiting for files in CDL folder…"
            await waitForFiles(in: desktop)

            // 4️⃣ Wait for thumb drive
            statusMessage = "Waiting for thumb drive…"
            await waitForDrive(at: volume)

            // 5️⃣ Check if thumb drive is meaningfully empty
            let visible = meaningfulContents(of: volume)
            if !visible.isEmpty {
                let choice = await confirmWipe(for: volume)
                switch choice {
                case .wipe:
                    do {
                        try removeContents(of: volume)
                        statusMessage = "Thumb drive wiped"
                    } catch {
                        statusMessage = "Failed to wipe thumb drive: \(error.localizedDescription)"
                        return
                    }
                case .skip:
                    break
                case .cancel:
                    statusMessage = "Workflow cancelled"
                    return
                }
            }

            // 6️⃣ Create thumb drive folder
            let volumeTarget = volume.appendingPathComponent(
                "Day \(shootingDay) \(breakName) CDLs and Framegrabs",
                isDirectory: true
            )

            do {
                try FileManager.default.createDirectory(at: volumeTarget, withIntermediateDirectories: true)
            } catch {
                statusMessage = "Failed to create folder on thumb drive"
                return
            }

            // 7️⃣ Copy deliverables
            do {
                try copyContents(from: desktop, to: volumeTarget)
            } catch {
                statusMessage = "Failed to copy files to thumb drive"
                return
            }

            // 8️⃣ Delete CDL files only
            deleteCDLFiles(in: desktop)

            // 9️⃣ Archive (Day X only)
            let archiveDay = archiveRoot.appendingPathComponent("Day \(shootingDay)", isDirectory: true)
            try? FileManager.default.createDirectory(at: archiveDay, withIntermediateDirectories: true)
            try? moveContents(from: desktop, to: archiveDay)

            // 🔟 Reveal + QC
            NSWorkspace.shared.open(volumeTarget)
            if let firstJPG = firstFile(withExtensions: ["jpg","jpeg"], in: volumeTarget) {
                NSWorkspace.shared.open(firstJPG)
            }

            statusMessage = "Workflow complete!"
        }
    }

    // MARK: - Waiting helpers

    func waitForFiles(in folder: URL) async {
        let fm = FileManager.default

        var lastSnapshot: (count: Int, size: Int64) = (0, 0)
        var stableSeconds = 0
        let requiredStableSeconds = 3
        var firstFileDetected = false
        var lastReportedCount = 0

        while true {
            guard let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                stableSeconds = 0
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let deliverables = items.filter { ["cdl", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }

            if !firstFileDetected && !deliverables.isEmpty {
                firstFileDetected = true
                await MainActor.run {
                    statusMessage = "Waiting for files to finish saving…"
                }
            }

            if firstFileDetected && deliverables.count != lastReportedCount {
                lastReportedCount = deliverables.count
                await MainActor.run {
                    statusMessage = "Waiting for files… (\(deliverables.count) file(s) detected)"
                }
            }

            if deliverables.isEmpty {
                stableSeconds = 0
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let count = deliverables.count
            let size = deliverables.reduce(Int64(0)) { total, url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                return total + Int64(values?.fileSize ?? 0)
            }

            if count == lastSnapshot.count && size == lastSnapshot.size {
                stableSeconds += 1
            } else {
                stableSeconds = 0
                lastSnapshot = (count, size)
            }

            if stableSeconds >= requiredStableSeconds {
                return
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func waitForDrive(at folder: URL) async {
        while !FileManager.default.fileExists(atPath: folder.path) {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

#Preview {
    ContentView()
}
