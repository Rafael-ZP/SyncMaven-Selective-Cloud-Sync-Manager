import Cocoa
internal import SwiftUI

final class MenuBarController: NSObject, NSApplicationDelegate {

    // Main objects
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var rightClickMenu: NSMenu!
    private var showDockIconMenuItem: NSMenuItem!
    
    @State private var isDockIconVisible = true

    // Icons
    private var baseIcon = NSImage(named: "MenubarIcon")
    private var syncingIcon = NSImage(named: "MenubarIconSync")   // Add this asset
    private var glowIcon = NSImage(named: "MenubarIconGlow")       // Optional glow effect

    // State
    private var isSyncing = false {
        didSet { updateIcon() }
    }
    private var glow = false {
        didSet { updateIcon() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenus()
        setupSyncListeners()
        
        // Set initial state
        isDockIconVisible = NSApp.activationPolicy() == .regular
        showDockIconMenuItem.state = isDockIconVisible ? .on : .off
    }

    // ----------------------------------------------------------
    // MARK: STATUS ITEM SETUP
    // ----------------------------------------------------------
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = baseIcon
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.action = #selector(handleClick(_:))
        }
    }

    // ----------------------------------------------------------
    // MARK: CLICK HANDLING
    // ----------------------------------------------------------
    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right click = menu
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { self.statusItem.menu = nil }
        } else {
            // Left click = main window
            showMainWindow()
        }
    }

    // ----------------------------------------------------------
    // MARK: MAIN WINDOW
    // ----------------------------------------------------------
    private func showMainWindow() {
        if mainWindow == nil {
            let content = MainWindow()
                .frame(minWidth: 700, minHeight: 500)

            mainWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [
                    .titled,
                    .closable,
                    .miniaturizable,
                    .resizable
                ],
                backing: .buffered,
                defer: false
            )

            mainWindow?.title = "Sinclo"
            mainWindow?.center()
            mainWindow?.isReleasedWhenClosed = false

            let hostingView = NSHostingView(rootView: content)
            hostingView.autoresizingMask = [.width, .height]
            mainWindow?.contentView = hostingView
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.collectionBehavior = .fullScreenPrimary
    }

    // ----------------------------------------------------------
    // MARK: MENUS
    // ----------------------------------------------------------
    private func setupMenus() {
        rightClickMenu = NSMenu()

        rightClickMenu.addItem(withTitle: "Open Sinclo Settings", action: #selector(openSettings), keyEquivalent: "")
        rightClickMenu.addItem(withTitle: "Accounts", action: #selector(openAccountsTab), keyEquivalent: "")
        rightClickMenu.addItem(withTitle: "Logs", action: #selector(openLogsTab), keyEquivalent: "")

        rightClickMenu.addItem(NSMenuItem.separator())

        showDockIconMenuItem = NSMenuItem(title: "Show Dock Icon", action: #selector(toggleDockIcon), keyEquivalent: "")
        rightClickMenu.addItem(showDockIconMenuItem)
        
        rightClickMenu.addItem(withTitle: "Quit Sinclo", action: #selector(quit), keyEquivalent: "q")
    }

    @objc private func openSettings()     { showMainWindow(); MainWindowTabsView.shared?.activateTab(.folders) }
    @objc private func openAccountsTab()  { showMainWindow(); MainWindowTabsView.shared?.activateTab(.accounts) }
    @objc private func openLogsTab()      { showMainWindow(); MainWindowTabsView.shared?.activateTab(.logs) }

    @objc private func toggleDockIcon() {
        isDockIconVisible.toggle()
        if isDockIconVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        showDockIconMenuItem.state = isDockIconVisible ? .on : .off
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // ----------------------------------------------------------
    // MARK: SYNC EVENTS (for icon animation)
    // ----------------------------------------------------------
    private func setupSyncListeners() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(startSync),
            name: Notification.Name("Sinclo.SyncStarted"),
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopSync),
            name: Notification.Name("Sinclo.SyncFinished"),
            object: nil
        )
    }

    @objc private func startSync() {
        DispatchQueue.main.async {
            self.isSyncing = true
            self.glow = true
            self.animateGlow()
        }
    }

    @objc private func stopSync() {
        DispatchQueue.main.async {
            self.isSyncing = false
            self.glow = false
        }
    }

    // ----------------------------------------------------------
    // MARK: ICON MANAGEMENT
    // ----------------------------------------------------------
    private func updateIcon() {
        if isSyncing, let icon = syncingIcon {
            statusItem.button?.image = icon
        } else if glow, let icon = glowIcon {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = baseIcon
        }
    }

    private func animateGlow() {
        guard glow else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.glow.toggle()
            self.updateIcon()
            if self.isSyncing { self.animateGlow() }
        }
    }
}
