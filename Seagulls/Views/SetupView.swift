//
//  SetupView.swift
//  Seagulls
//
//  Created by Andy Bader on 2/4/26.
//

import SwiftUI

struct SetupView: View {
    @Binding var desktopCDLURL: URL?
    @Binding var archiveRootURL: URL?
    @Binding var volumeURL: URL?
    @Binding var statusMessage: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Setup Folders").font(.title)
            
            folderPicker(label: "Desktop CDL Folder", url: $desktopCDLURL)
            folderPicker(label: "Archive Root", url: $archiveRootURL)
            folderPicker(label: "Thumb Drive Volume", url: $volumeURL)
            
            Divider()
            
            Button("Save Settings") {
                saveSettings()
            }
            .disabled(desktopCDLURL == nil || archiveRootURL == nil || volumeURL == nil)
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
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
            Button("Choose…") {
                chooseFolder(for: url)
            }
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
    
    // MARK: - Save Settings to JSON
    func saveSettings() {
        guard let desktop = desktopCDLURL,
              let archive = archiveRootURL,
              let volume = volumeURL else { return }
        
        do {
            // Convert URLs to bookmarks for sandbox-safe storage
            let settings = try CDLSettings(desktopURL: desktop, archiveURL: archive, volumeURL: volume)
            
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
}
