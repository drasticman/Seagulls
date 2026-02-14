//
//  SetupView.swift
//  Seagulls
//
//  Updated 2/14/26 — scrollable trusted drives, fixed UUID optional binding, TrustedDriveRow
//

import SwiftUI

struct SetupView: View {
    @Binding var desktopCDLURL: URL?
    @Binding var archiveRootURL: URL?
    @Binding var volumeURL: URL?
    @Binding var statusMessage: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var driveRegistry = DriveRegistryModel.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("Setup Folders")
                .font(.title)

            // MARK: - Folder Pickers
            folderPicker(label: "Desktop CDL Folder", url: $desktopCDLURL)
            folderPicker(label: "Archive Root", url: $archiveRootURL)

            Divider()

            // MARK: - Trusted Drives List
            VStack(alignment: .leading, spacing: 10) {
                Text("Trusted Drives")
                    .font(.headline)

                ScrollView {
                    let trusted = driveRegistry.allTrusted()
                    let sortedTrusted = trusted.sorted { $0.addedAt < $1.addedAt }

                    if sortedTrusted.isEmpty {
                        Text("No drives are currently trusted.")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.top, 6)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(sortedTrusted, id: \.id) { drive in
                                TrustedDriveRow(
                                    drive: drive,
                                    isMounted: isDriveMounted(drive),
                                    untrustAction: {
                                        Task { @MainActor in
                                            driveRegistry.untrust(drive)
                                            if let vol = volumeURL,
                                               vol.lastPathComponent == drive.volumeName {
                                                volumeURL = nil
                                            }
                                            statusMessage = "Drive \(drive.volumeName ?? "Unknown") untrusted"
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxHeight: 200)

                Button("Forget All Trusted Drives") {
                    Task { @MainActor in
                        driveRegistry.forgetAll()
                        volumeURL = nil
                        statusMessage = "All trusted drives forgotten"
                    }
                }
                .foregroundColor(.red)
                .padding(.top, 6)
            }

            Divider()

            // MARK: - Save Settings
            Button("Save Settings") {
                saveSettings()
            }
            .disabled(desktopCDLURL == nil || archiveRootURL == nil)
            .padding(.top, 6)

            Spacer()
        }
        .padding()
        .frame(minWidth: 520, minHeight: 500)
    }

    // MARK: - Folder Picker
    @ViewBuilder
    func folderPicker(label: String, url: Binding<URL?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(url.wrappedValue?.path ?? "Not set")
                .lineLimit(1)
                .truncationMode(.middle)
            Button("Choose…") { chooseFolder(for: url) }
        }
    }

    func chooseFolder(for url: Binding<URL?>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.directoryURL = url.wrappedValue

        if panel.runModal() == .OK, let selected = panel.url {
            url.wrappedValue = selected
        }
    }

    // MARK: - Save Settings
    func saveSettings() {
        guard let desktop = desktopCDLURL,
              let archive = archiveRootURL else { return }

        do {
            let settings = try CDLSettings(
                desktopURL: desktop,
                archiveURL: archive,
                volumeURL: volumeURL ?? desktop // fallback
            )

            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Seagulls")
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let fileURL = appSupport.appendingPathComponent("settings.json")
            let data = try JSONEncoder().encode(settings)
            try data.write(to: fileURL)

            statusMessage = "Settings saved"
            dismiss()
        } catch {
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers
    func isDriveMounted(_ drive: TrustedDrive) -> Bool {
        guard let vol = volumeURL,
              let mountedUUID = try? vol.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString else {
            return false
        }
        return mountedUUID == drive.volumeUUID.uuidString
    }
}

// MARK: - Trusted Drive Row Subview
struct TrustedDriveRow: View {
    let drive: TrustedDrive
    var isMounted: Bool
    var untrustAction: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(drive.volumeName ?? "Unknown")
                    .fontWeight(.medium)
                if let capacity = drive.capacityBytes {
                    Text("\(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Added: \(drive.addedAt.formatted(date: .numeric, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isMounted {
                Text("Mounted")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            Button("Untrust", action: untrustAction)
                .buttonStyle(BorderlessButtonStyle())
                .foregroundColor(.red)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.05)))
    }
}

// MARK: - Preview
#Preview {
    SetupView(
        desktopCDLURL: .constant(nil),
        archiveRootURL: .constant(nil),
        volumeURL: .constant(nil),
        statusMessage: .constant("Ready")
    )
}
