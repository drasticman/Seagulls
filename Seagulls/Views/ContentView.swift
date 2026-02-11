//
//  ContentView.swift
//  Seagulls
//
//  Created by Andy Bader on 2/4/26
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
                    .disabled(volumeURL == nil)   // 👈 key UX detail
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
            logAllMountedVolumes()
            loadSettings()
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
        for drive in mountedRemovableDrives() {
            print("Mounted removable drive:")
            print("  name:", drive.volumeName ?? "nil")
            print("  uuid:", drive.volumeUUID?.uuidString ?? "nil")
            print("  capacity:", drive.capacityBytes ?? 0)
            print("  path:", drive.url.path)
        }

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
        startVolumeWatcher()

        desktopCDLURL = settings.desktopCDLURL()
        archiveRootURL = settings.archiveRootURL()
        volumeURL = settings.volumeURL()

        if volumeURL == nil {
            statusMessage = "Settings loaded — waiting for thumb drive"
        } else {
            statusMessage = "Settings loaded"
        }
    }



    // MARK: - Main Workflow

    func startWorkflow() {
        guard let desktop = desktopCDLURL,
              let archiveRoot = archiveRootURL,
              let volume = volumeURL else { return }

        Task {

            // 1️⃣ Shooting day
            let shootingDay = await askText(
                title: "Shooting Day",
                message: "Enter the shooting day (e.g. 6):"
            )
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

            if let firstJPG = firstFile(
                withExtensions: ["jpg", "jpeg"],
                in: volumeTarget
            ) {
                NSWorkspace.shared.open(firstJPG)
            }

            statusMessage = "Workflow complete!"
        }
    }

    // MARK: - Alerts

    func askText(title: String, message: String) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = title
                alert.informativeText = message

                let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
                alert.accessoryView = field

                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")

                let result = alert.runModal()
                continuation.resume(
                    returning: result == .alertFirstButtonReturn
                        ? field.stringValue
                        : ""
                )
            }
        }
    }

    func askBreak() async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Break"
                alert.informativeText = "Select the break"

                let combo = NSComboBox(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
                combo.addItems(withObjectValues: ["AM", "PM", "All Day"])
                combo.selectItem(at: 0)
                alert.accessoryView = combo

                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Cancel")

                let result = alert.runModal()
                continuation.resume(
                    returning: result == .alertFirstButtonReturn
                        ? (combo.stringValue.isEmpty ? "All Day" : combo.stringValue)
                        : ""
                )
            }
        }
    }



    enum WipeChoice {
        case wipe
        case skip
        case cancel
    }

    func confirmWipe() async -> WipeChoice {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Thumb drive not empty"
                alert.informativeText = "Wipe the thumb drive?"
                alert.alertStyle = .warning

                alert.addButton(withTitle: "Wipe")
                alert.addButton(withTitle: "Skip")
                alert.addButton(withTitle: "Cancel")

                switch alert.runModal() {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: .wipe)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: .skip)
                default:
                    continuation.resume(returning: .cancel)
                }
            }
        }
    }

    // MARK: - File Helpers

    func meaningfulContents(of folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isHiddenKey]
        ) else { return [] }

        return items.filter {
            !((try? $0.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? true)
        }
    }

    func removeContents(of folder: URL) throws {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isHiddenKey]
        )

        for item in items {
            let isHidden = (try? item.resourceValues(forKeys: [.isHiddenKey]).isHidden) ?? true
            if isHidden { continue }
            try fm.removeItem(at: item)
        }
    }

    func copyContents(from src: URL, to dst: URL) throws {
        let items = try FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for item in items {
            let target = dst.appendingPathComponent(item.lastPathComponent)
            try FileManager.default.copyItem(at: item, to: target)
        }
    }

    func moveContents(from src: URL, to dst: URL) throws {
        let items = try FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for item in items {
            try FileManager.default.moveItem(
                at: item,
                to: dst.appendingPathComponent(item.lastPathComponent)
            )
        }
    }

    func deleteCDLFiles(in folder: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return }

        for item in items where item.pathExtension.lowercased() == "cdl" {
            try? FileManager.default.removeItem(at: item)
        }
    }

    func firstFile(withExtensions exts: [String], in folder: URL) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return nil }

        return items.first {
            exts.contains($0.pathExtension.lowercased())
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
                try? await Task.sleep(nanoseconds: 1_000_000_000)
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
    
    func startVolumeWatcher() {
        volumeWatcherTask?.cancel()

        guard let settings = loadedSettings else { return }

        volumeWatcherTask = Task {
            while !Task.isCancelled {
                // Already mounted? Nothing to do.
                if volumeURL != nil {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }

                if let resolved = settings.volumeURL() {
                    await MainActor.run {
                        volumeURL = resolved
                        statusMessage = "Thumb drive detected"
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

}

#Preview {
    ContentView()
}
