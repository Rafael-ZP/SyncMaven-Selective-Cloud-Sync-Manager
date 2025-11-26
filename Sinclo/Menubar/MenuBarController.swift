import Cocoa
import SwiftUI

final class MenuBarController: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow!
    let syncManager = SyncManager.shared

    // small menu for right-click or menu fallback
    lazy var statusMenu: NSMenu = {
        let m = NSMenu()
        m.addItem(withTitle: "Sinclo Settings", action: #selector(showWindowFromMenu(_:)), keyEquivalent: "")
        m.addItem(NSMenuItem.separator())
        let dockItem = NSMenuItem(title: "Show in Dock", action: #selector(toggleDock(_:)), keyEquivalent: "")
        dockItem.state = UserDefaults.standard.bool(forKey: "Sinclo.ShowInDock") ? .on : .off
        m.addItem(dockItem)
        m.addItem(NSMenuItem.separator())
        m.addItem(withTitle: "Quit Sinclo", action: #selector(quitApp(_:)), keyEquivalent: "q")
        return m
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // decide dock policy on launch
        applyDockPolicy()

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(named: "MenubarIcon")
            // accept left and right mouse up events
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        // Build window (hidden by default) — Tab window
        let content = AppWindowView().environmentObject(AppState.shared)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Sinclo"
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false

        // Start core services (monitoring)
        syncManager.startMonitoringAll()
    }

    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            // show menu at statusItem location
            statusItem.popUpMenu(statusMenu)
        } else {
            // left click → show window
            showWindow(nil)
        }
    }

    @objc func showWindowFromMenu(_ sender: Any?) {
        showWindow(nil)
    }

    @objc func showWindow(_ sender: Any?) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleDock(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: "Sinclo.ShowInDock")
        UserDefaults.standard.set(!current, forKey: "Sinclo.ShowInDock")
        sender.state = !current ? .on : .off
        applyDockPolicy()
    }

    private func applyDockPolicy() {
        let showInDock = UserDefaults.standard.bool(forKey: "Sinclo.ShowInDock")
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
    }

    @objc func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }
}
