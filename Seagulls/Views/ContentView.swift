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
    @State private var isRunning = false

    @State private var untrustedDrives: [MountedDrive] = []

    @StateObject private var driveRegistry = DriveRegistryModel.shared

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

            // ✅ Automatically show setup on first run
            if !settingsLoaded {
                showingSetup = true
            }
        }

        .onDisappear {
            volumeWatcherTask?.cancel()
        }

        .onChange(of: showingSetup) { _, isShowing in
            if !isShowing {
                loadSettings()
                evaluateSetupCompletion()
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

        volumeWatcherTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                refreshMountedDrives()
            }
        }
    }

    @MainActor
    func refreshMountedDrives() {
        let mounted = mountedRemovableDrives()
        let candidates = candidateDrives(from: mounted).map { $0.mountedDrive }

        if let trustedDrive = candidates.first(where: { driveRegistry.isTrusted($0) }) {
            if volumeURL != trustedDrive.url {
                withAnimation(.easeInOut(duration: 0.2)) {
                    volumeURL = trustedDrive.url
                }
                statusMessage = "\(trustedDrive.volumeName ?? "Thumb drive") detected — ready to start"
            }

        } else if volumeURL != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                volumeURL = nil
            }
            statusMessage = "Trusted thumb drive disconnected"
        }

        untrustedDrives = candidates.filter { !driveRegistry.isTrusted($0) }
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

        Task { @MainActor in
            defer { isRunning = false }

            let shootingDay = await askText(title: "Shooting Day", message: "Enter the shooting day (e.g. 6):")
            guard !shootingDay.isEmpty else {
                statusMessage = "Workflow cancelled"
                return
            }

            let breakName = await askBreak()
            guard !breakName.isEmpty else {
                statusMessage = "Workflow cancelled"
                return
            }

            statusMessage = "Waiting for files in CDL folder…"
            await waitForFiles(in: desktop)

            statusMessage = "Waiting for thumb drive…"
            await waitForDrive(at: volume)

            let visible = meaningfulContents(of: volume)
            if !visible.isEmpty {
                let choice = await confirmWipe(for: volume)
                switch choice {
                case .wipe:
                    try? removeContents(of: volume)
                case .skip:
                    break
                case .cancel:
                    statusMessage = "Workflow cancelled"
                    return
                }
            }

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
            if let firstJPG = firstFile(withExtensions: ["jpg","jpeg"], in: volumeTarget) {
                NSWorkspace.shared.open(firstJPG)
            }

            statusMessage = "Workflow complete!"
        }
    }

    // MARK: - Waiting helpers

    func waitForFiles(in folder: URL) async {
        let fm = FileManager.default
        var lastSnapshot: (cdlCount: Int, jpgCount: Int, size: Int64) = (0, 0, 0)
        var stableSeconds = 0
        let requiredStableSeconds = 3

        while true {
            guard let items = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run {
                    statusMessage = "Waiting for files… (cannot read folder)"
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            let cdls = items.filter { $0.pathExtension.lowercased() == "cdl" }
            let jpgs = items.filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            let deliverables = cdls + jpgs

            // Live status update
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
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            // Compute total size to detect “still copying”
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

            // Optional: show stabilization progress once files exist
            await MainActor.run {
                statusMessage = "Waiting for files… (CDLs: \(cdls.count), JPGs: \(jpgs.count), stable \(stableSeconds)/\(requiredStableSeconds))"
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
