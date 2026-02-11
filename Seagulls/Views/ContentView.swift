//
//  ContentView.swift
//  Seagulls
//
//  Created by Andy Bader on 2/4/26
//  Updated 2/11/26 — compiled stubs added
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
                    } else {
                        Text("Thumb Drive Volume: Not mounted")
                            .foregroundColor(.secondary)
                    }

                    Button("Change Settings") { showingSetup = true }

                    Divider()

                    Button("Start Workflow") {
                        startWorkflow()
                    }
                    .disabled(volumeURL == nil)
                    .keyboardShortcut(.defaultAction)
                }

            } else {
                Text("No settings found.")
                Button("Setup Folders") { showingSetup = true }
            }

            Divider()

            Text("Status: \(statusMessage)")
                .foregroundColor(.gray)
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

    // MARK: - Refresh Drives

    func refreshMountedDrives() {
        let mounted = mountedRemovableDrives()
        let candidates = candidateDrives(from: mounted)

        // Look for DIT_CDLs specifically (name-based for now)
        let detectedDrive = candidates
            .map { $0.mountedDrive }
            .first { $0.volumeName == "DIT_CDLs" }

        if let drive = detectedDrive {
            // Drive is present
            if volumeURL != drive.url {
                volumeURL = drive.url
                statusMessage = "DIT_CDLs thumb drive detected — ready to start"
            }
        } else {
            // Drive is NOT present
            if volumeURL != nil {
                volumeURL = nil
                statusMessage = "DIT_CDLs thumb drive disconnected"
            }
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
            statusMessage = "No settings found — please set up folders"
            settingsLoaded = false
            loadedSettings = nil
            return
        }

        loadedSettings = settings
        settingsLoaded = true

        desktopCDLURL = settings.desktopCDLURL()
        archiveRootURL = settings.archiveRootURL()
        volumeURL = settings.volumeURL()

        if volumeURL == nil {
            statusMessage = "Settings loaded — waiting for thumb drive"
        } else {
            statusMessage = "Settings loaded"
        }

        startVolumeWatcher()
    }

    // MARK: - Volume watcher (poll for new mounts)

    func startVolumeWatcher() {
        volumeWatcherTask?.cancel()

        volumeWatcherTask = Task {
            while !Task.isCancelled {
                refreshMountedDrives()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }


    // MARK: - Main Workflow

    func startWorkflow() {
        guard let desktop = desktopCDLURL,
              let archiveRoot = archiveRootURL,
              let volume = volumeURL else { return }

        Task {

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

            // 3️⃣ Wait for files
            statusMessage = "Waiting for files in CDL folder…"
            await waitForFiles(in: desktop)

            // 4️⃣ Wait for thumb drive
            statusMessage = "Waiting for thumb drive…"
            await waitForDrive(at: volume)

            // 5️⃣ Check thumb drive contents
            let visible = meaningfulContents(of: volume)
            if !visible.isEmpty {
                let choice = await confirmWipe()
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
                try FileManager.default.createDirectory(
                    at: volumeTarget,
                    withIntermediateDirectories: true
                )
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
            let archiveDay = archiveRoot.appendingPathComponent(
                "Day \(shootingDay)",
                isDirectory: true
            )

            try? FileManager.default.createDirectory(
                at: archiveDay,
                withIntermediateDirectories: true
            )

            try? moveContents(from: desktop, to: archiveDay)

            // 🔟 Reveal + QC
            NSWorkspace.shared.open(volumeTarget)

            if let firstJPG = firstFile(withExtensions: ["jpg", "jpeg"], in: volumeTarget) {
                NSWorkspace.shared.open(firstJPG)
            }

            statusMessage = "Workflow complete!"
        }
    }

    // MARK: - Waiting

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
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            let deliverables = items.filter {
                ["cdl", "jpg", "jpeg"].contains($0.pathExtension.lowercased())
            }

            if !firstFileDetected && !deliverables.isEmpty {
                firstFileDetected = true
                DispatchQueue.main.async {
                    statusMessage = "Waiting for files to finish saving…"
                }
            }

            if firstFileDetected && deliverables.count != lastReportedCount {
                lastReportedCount = deliverables.count
                DispatchQueue.main.async {
                    statusMessage = "Waiting for files… (\(deliverables.count) file(s) detected)"
                }
            }

            if deliverables.isEmpty {
                stableSeconds = 0
                try? await Task.sleep(nanoseconds: 500_000_000)
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

            try? await Task.sleep(nanoseconds: 500_000_000)
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
