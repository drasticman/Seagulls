import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Install Stream Deck Plugin...") {
                StreamDeckInstaller.shared.installFromMenu()
            }
        }
    }
}
