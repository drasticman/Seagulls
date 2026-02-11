//
//  WorkflowHelpers.swift
//  Seagulls
//
//  Created by Andy Bader on 2/11/26.
//

import Foundation
import AppKit

// MARK: - WipeChoice enum
enum WipeChoice {
    case wipe
    case skip
    case cancel
}

// MARK: - Placeholder functions for workflow

/// Asks the user for free-text input
func askText(title: String, message: String) async -> String {
    await withCheckedContinuation { continuation in
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        // Simple text field
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


/// Asks the user to enter a break name
func askBreak() async -> String {
    await withCheckedContinuation { continuation in
        let alert = NSAlert()
        alert.messageText = "Break / AM-PM"
        alert.informativeText = "Select or type a break designation:"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        
        // ✅ Create editable combo box
        let comboBox = NSComboBox(frame: NSRect(x: 0, y: 0, width: 150, height: 26))
        comboBox.addItems(withObjectValues: ["AM", "PM", "All Day"])
        comboBox.selectItem(at: 0)   // default to "AM"
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


/// Returns meaningful contents of a folder (non-hidden files)
func meaningfulContents(of folder: URL) -> [URL] {
    let fm = FileManager.default
    return (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { !$0.lastPathComponent.hasPrefix(".") }) ?? []
}

/// Prompts the user to confirm wiping a thumb drive
func confirmWipe() async -> WipeChoice {
    return .skip
}

/// Removes all contents of a folder
func removeContents(of folder: URL) throws {
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    for item in items {
        try fm.removeItem(at: item)
    }
}

/// Copies contents from one folder to another
func copyContents(from src: URL, to dst: URL) throws {
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
    for item in items {
        let destURL = dst.appendingPathComponent(item.lastPathComponent)
        try fm.copyItem(at: item, to: destURL)
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

/// Moves contents from one folder to another
func moveContents(from src: URL, to dst: URL) throws {
    let fm = FileManager.default
    let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
    for item in items {
        let destURL = dst.appendingPathComponent(item.lastPathComponent)
        try fm.moveItem(at: item, to: destURL)
    }
}

/// Returns the first file with a matching extension in a folder
func firstFile(withExtensions exts: [String], in folder: URL) -> URL? {
    let fm = FileManager.default
    guard let items = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
    return items.first { exts.contains($0.pathExtension.lowercased()) }
}

// MARK: - CDLSettings extension for volumeName

extension CDLSettings {
    func volumeName() -> String? {
        return volumeURL()?.lastPathComponent
    }
}

// MARK: - autoTrust helper (uses DriveRegistry)

func autoTrust(_ drive: MountedDrive) {
    DriveRegistry.shared.registerCandidate(drive)
}
