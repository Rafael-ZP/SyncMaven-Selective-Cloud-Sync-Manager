internal import SwiftUI

@main
struct SincloApp: App {
    @NSApplicationDelegateAdaptor(MenuBarController.self) var appDelegate

    var body: some Scene {
        Settings{
            EmptyView()
        }
    }
}
