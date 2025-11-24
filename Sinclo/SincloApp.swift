import SwiftUI

@main
struct SincloApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Sinclo", systemImage: "externaldrive") {
            StatusMenuView()    // <-- This shows the dropdown menu
        }
        .menuBarExtraStyle(.window)   // Important
    }
}
