import Cocoa
import SwiftUI

final class MenuBarController: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    let syncManager = SyncManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "MenubarIcon")
            button.action = #selector(showWindow(_:))
            button.target = self
        }

        // Build window (hidden by default)
        let content = AppWindowView().environmentObject(syncManager)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Sinclo"
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false

        // Start core services
        syncManager.startMonitoringAll()
    }

    @objc func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
