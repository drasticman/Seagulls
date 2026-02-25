import Foundation
import AppKit

@MainActor
final class StreamDeckInstaller {
    static let shared = StreamDeckInstaller()

    private let fileManager = FileManager.default

    private let skipPromptKey = "SkipStreamDeckPluginInstallPrompt"
    private let bundledPluginName = "Seagulls"
    private let bundledPluginExtension = "sdPlugin"
    private let legacyPluginFolderName = "xyz.tailwindtech.dit.streamdeckpluginsandbox.sdPlugin"

    private var promptedThisSession = false

    private init() {}

    private enum PluginState {
        case missing
        case installedCurrent
        case updateAvailable
    }

    private struct PromptDecision {
        let install: Bool
        let dontAskAgain: Bool
    }

    var destinationPluginURL: URL {
        pluginsDirectoryURL.appendingPathComponent("\(bundledPluginName).\(bundledPluginExtension)")
    }

    private var pluginsDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.elgato.StreamDeck/Plugins", isDirectory: true)
    }

    private var legacyPluginURL: URL {
        pluginsDirectoryURL.appendingPathComponent(legacyPluginFolderName)
    }

    private var bundledPluginURL: URL? {
        Bundle.main.url(forResource: bundledPluginName, withExtension: bundledPluginExtension)
    }

    func installFromMenu() {
        do {
            try installPluginReplacingExisting()
            UserDefaults.standard.set(false, forKey: skipPromptKey)
            showInfoAlert(
                title: "Stream Deck plugin installed. Restart Stream Deck to activate.",
                message: ""
            )
        } catch {
            showErrorAlert(error)
        }
    }

    func promptForInstallOrUpdateIfNeeded() {
        guard !promptedThisSession else { return }
        guard isStreamDeckLikelyInstalled() else { return }
        guard !UserDefaults.standard.bool(forKey: skipPromptKey) else { return }

        switch pluginState() {
        case .installedCurrent:
            return
        case .missing:
            promptedThisSession = true
            let decision = presentInstallPrompt(
                title: "Install Stream Deck Plugin?",
                message: "Seagulls can install its Stream Deck plugin automatically."
            )
            handlePromptDecision(decision)
        case .updateAvailable:
            promptedThisSession = true
            let decision = presentInstallPrompt(
                title: "Update Stream Deck Plugin?",
                message: "A newer bundled Stream Deck plugin is available."
            )
            handlePromptDecision(decision)
        }
    }

    private func handlePromptDecision(_ decision: PromptDecision) {
        if decision.dontAskAgain {
            UserDefaults.standard.set(true, forKey: skipPromptKey)
        }

        guard decision.install else { return }

        do {
            try installPluginReplacingExisting()
            UserDefaults.standard.set(false, forKey: skipPromptKey)
            showInfoAlert(
                title: "Stream Deck plugin installed. Restart Stream Deck to activate.",
                message: ""
            )
        } catch {
            showErrorAlert(error)
        }
    }

    private func installPluginReplacingExisting() throws {
        guard let bundledPluginURL else {
            throw NSError(
                domain: "Seagulls.StreamDeckInstaller",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Bundled Stream Deck plugin was not found in app resources."]
            )
        }

        try fileManager.createDirectory(at: pluginsDirectoryURL, withIntermediateDirectories: true, attributes: nil)

        if fileManager.fileExists(atPath: destinationPluginURL.path) {
            try fileManager.removeItem(at: destinationPluginURL)
        }

        if fileManager.fileExists(atPath: legacyPluginURL.path) {
            try fileManager.removeItem(at: legacyPluginURL)
        }

        try fileManager.copyItem(at: bundledPluginURL, to: destinationPluginURL)
    }

    private func pluginState() -> PluginState {
        guard bundledPluginURL != nil else {
            return .installedCurrent
        }

        guard let installedPluginURL = installedPluginCandidateURL() else {
            return .missing
        }

        if installedPluginURL.path != destinationPluginURL.path {
            return .updateAvailable
        }

        let bundledVersion = manifestVersion(at: bundledPluginURL)
        let installedVersion = manifestVersion(at: installedPluginURL)

        guard let bundledVersion, let installedVersion else {
            return .updateAvailable
        }

        return bundledVersion == installedVersion ? .installedCurrent : .updateAvailable
    }

    private func installedPluginCandidateURL() -> URL? {
        if fileManager.fileExists(atPath: destinationPluginURL.path) {
            return destinationPluginURL
        }

        if fileManager.fileExists(atPath: legacyPluginURL.path) {
            return legacyPluginURL
        }

        return nil
    }

    private func manifestVersion(at pluginURL: URL?) -> String? {
        guard let pluginURL else { return nil }

        let manifestURL = pluginURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let version = object["Version"] as? String {
            return version
        }

        if let version = object["version"] as? String {
            return version
        }

        return nil
    }

    private func isStreamDeckLikelyInstalled() -> Bool {
        if fileManager.fileExists(atPath: "/Applications/Stream Deck.app") {
            return true
        }

        if fileManager.fileExists(atPath: pluginsDirectoryURL.path) {
            return true
        }

        return !NSRunningApplication.runningApplications(withBundleIdentifier: "com.elgato.StreamDeck").isEmpty
    }

    private func presentInstallPrompt(title: String, message: String) -> PromptDecision {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not Now")

        let dontAskAgain = NSButton(checkboxWithTitle: "Don't ask again", target: nil, action: nil)
        alert.accessoryView = dontAskAgain

        let response = alert.runModal()
        return PromptDecision(
            install: response == .alertFirstButtonReturn,
            dontAskAgain: dontAskAgain.state == .on
        )
    }

    private func showInfoAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Stream Deck plugin install failed."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
