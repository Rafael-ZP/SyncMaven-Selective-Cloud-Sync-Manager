// SincloApp.swift
// Sinclo

internal import SwiftUI

@main
struct SyncMaven: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Sinclo Settings...") {
                    // Safe access
                    MenuBarController.shared.showMainWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandGroup(replacing: .newItem) {
                Button("Add Watched Folder") {
                    MenuBarController.shared.showMainWindow()
                    AppState.shared.pickLocalFolder()
                }
                .keyboardShortcut("N", modifiers: .command)
            }
        }
    }
}
