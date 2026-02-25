//
//  SeagullsApp.swift
//

import SwiftUI
import SwiftData

@main
struct SeagullsApp: App {

    @Environment(\.openWindow) private var openWindow

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    LocalControlServer.shared.start(port: 7070)
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            AppCommands()
            CommandGroup(replacing: .help) {
                Button("Seagulls Help") {
                    openWindow(id: "help")
                }
            }
        }

        // Floating Help Window
        Window("Seagulls Help", id: "help") {
            HelpView()
                .background(WindowLevelAccessor(level: .floating))
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
    }

}
