//
//  WorkflowHelpers.swift
//  Seagulls
//
//  Created by Andy Bader on 2/11/26
//  Updated 2/13/26 — full workflow helpers including safe wipe and Finder integration
//

import Foundation
import AppKit

// MARK: - WipeChoice enum
enum WipeChoice {
    case wipe
    case skip
    case cancel
}

// MARK: - User prompts

/// Asks the user for free-text input (returns empty string if cancelled)
func askText(title: String, message: String) async -> String {
    await withCheckedContinuation { continuation in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = input
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            continuation.resume(returning: input.stringValue)
        } else {
            continuation.resume(returning: "")
        }
    }
}

/// Asks the user to enter a break name (AM/PM/All Day)
func askBreak() async -> String {
    await withCheckedContinuation { continuation in
        let alert = NSAlert()
        alert.messageText = "Break / AM-PM"
        alert.informativeText = "Select or type a break designation:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        let comboBox = NSComboBox(frame: NSRect(x: 0, y: 0, width: 150, height: 26))
        comboBox.addItems(withObjectValues: ["AM", "PM", "All Day"])
        comboBox.selectItem(at: 0)
        comboBox.isEditable = true
        
        alert.accessoryView = comboBox
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            continuation.resume(returning: comboBox.stringValue)
        } else {
            continuation.resume(returning: "")
        }
    }
}

/// Ask user whether to wipe a non-empty thumb drive, showing its root folder in Finder
/// with all files selected for inspection
func confirmWipe(for volume: URL) async -> WipeChoice {
    let fm = FileManager.default
    let items = (try? fm.contentsOfDirectory(at: volume, includingPropertiesForKeys: nil)
                    .filter { !$0.lastPathComponent.hasPrefix(".") }) ?? []

    if !items.isEmpty {
        // AppleScript: open folder, bring Finder to front, select files
        let appleScript = """
        tell application "Finder"
            activate
            set theFolder to POSIX file "\(volume.path)" as alias
            open theFolder
            select { \(items.map { "POSIX file \"\($0.path)\" as alias" }.joined(separator: ", ")) }
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: appleScript) {
            script.executeAndReturnError(&error)
            if let err = error {
                print("⚠️ AppleScript failed: \(err)")
            }
        }

        // Optional: wait 0.3s to ensure Finder has time to bring window forward
        try? await Task.sleep(nanoseconds: 300_000_000)
    } else {
        NSWorkspace.shared.open(volume)
    }

    return await withCheckedContinuation { continuation in
        let alert = NSAlert()
        alert.messageText = "Thumb Drive Not Empty"
        alert.informativeText = "Files already exist on this drive. Do you want to wipe it, continue without wiping, or cancel the workflow?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Wipe")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            continuation.resume(returning: .wipe)
        case .alertSecondButtonReturn:
            continuation.resume(returning: .skip)
        default:
            continuation.resume(returning: .cancel)
        }
    }
}

// MARK: - File system helpers

/// Returns non-hidden contents of a folder
func meaningfulContents(of folder: URL) -> [URL] {
    let fm = FileManager.default
    return (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { !$0.lastPathComponent.hasPrefix(".") }) ?? []
}

/// Removes all user-writable contents of a folder (skips system-protected items)
func removeContents(of folder: URL) throws {
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)

    for item in items {
        let name = item.lastPathComponent
        if name.hasPrefix(".") || name == ".DocumentRevisions-V100" || name == ".Spotlight-V100" {
            continue
        }

        do {
            try fm.trashItem(at: item, resultingItemURL: nil)
        } catch {
            print("⚠️ Skipped item due to error: \(item.path) — \(error)")
        }
    }
}

/// Copies all contents from one folder to another
func copyContents(from src: URL, to dst: URL) throws {
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
    for item in items {
        let destURL = dst.appendingPathComponent(item.lastPathComponent)
        try fm.copyItem(at: item, to: destURL)
    }
}

/// Moves all contents from one folder to another
func moveContents(from src: URL, to dst: URL) throws {
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
    for item in items {
        let destURL = dst.appendingPathComponent(item.lastPathComponent)
        try fm.moveItem(at: item, to: destURL)
    }
}

/// Deletes only CDL files from a folder
func deleteCDLFiles(in folder: URL) {
    let fm = FileManager.default
    if let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
        for item in items where item.pathExtension.lowercased() == "cdl" {
            try? fm.removeItem(at: item)
        }
    }
}

/// Returns the first file with a matching extension in a folder
func firstFile(withExtensions exts: [String], in folder: URL) -> URL? {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
    return items.first { exts.contains($0.pathExtension.lowercased()) }
}


