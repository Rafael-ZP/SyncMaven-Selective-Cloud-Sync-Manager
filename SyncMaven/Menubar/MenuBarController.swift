// MenuBarController.swift
// SyncMaven
// Fixed: Singleton Logic & Layout Recursion

import Cocoa
internal import SwiftUI

final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    // 1. Weak static reference to avoid retainer cycles/double init
    static private(set) var sharedController: MenuBarController?
    
    // Helper to safely access the live instance
    static var shared: MenuBarController {
        guard let ref = sharedController else {
            fatalError("MenuBarController not initialized yet")
        }
        return ref
    }

    // Main objects
    private var statusItem: NSStatusItem!
    private var mainWindow: NSWindow?
    private var popover: NSPopover!
    private var rightClickMenu: NSMenu!
    
    // Logic State
    private var eventMonitor: Any?
    @AppStorage("showDockIcon") private var isDockIconVisible = true

    // Icons
    private var baseIcon = NSImage(named: "MenubarIcon")
    private var syncingIcon = NSImage(named: "MenubarIconSync")
    private var glowIcon = NSImage(named: "MenubarIconGlow")
    
    // Sync State
    private var isSyncing = false { didSet { updateIcon() } }
    private var glow = false { didSet { updateIcon() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
            MenuBarController.sharedController = self
            
            setupStatusItem()
            setupPopover()
            setupMenus()
            setupSyncListeners()
            updateDockIconState()
            
            // FIX: Start monitoring AFTER AppState init is 100% complete
            DispatchQueue.main.async {
                AppState.shared.restoreMonitoring()
            }
        }

    // ----------------------------------------------------------
    // MARK: STATUS ITEM & CLICKS
    // ----------------------------------------------------------
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = baseIcon
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            // Right Click -> Show Menu
            statusItem.menu = rightClickMenu
            statusItem.button?.performClick(nil) // Trigger menu
            statusItem.menu = nil // Reset so left click works next time
        } else {
            // Left Click -> Toggle Popover
            // 3. Dispatch Async to prevent Layout Recursion Error
            DispatchQueue.main.async {
                self.togglePopover(sender)
            }
        }
    }

    // ----------------------------------------------------------
    // MARK: POPOVER (Left Click)
    // ----------------------------------------------------------
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        // Pass the shared instance implicitly via Environment or Singleton access in View
        popover.contentViewController = NSHostingController(rootView: QuickStatusView())
        popover.delegate = self
    }
    
    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            if let button = statusItem.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    func closePopover() {
        popover.performClose(nil)
    }

    // ----------------------------------------------------------
    // MARK: MAIN WINDOW
    // ----------------------------------------------------------
    func showMainWindow() {
        // 3. Dispatch Async here too
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            if self.mainWindow == nil {
                let content = MainWindow()
                    .frame(minWidth: 700, minHeight: 500)

                self.mainWindow = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                    backing: .buffered,
                    defer: false
                )
                self.mainWindow?.title = "SyncMaven Settings"
                self.mainWindow?.center()
                self.mainWindow?.isReleasedWhenClosed = false
                self.mainWindow?.contentView = NSHostingView(rootView: content)
            }

            self.mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // ----------------------------------------------------------
    // MARK: RIGHT CLICK MENU
    // ----------------------------------------------------------
    private func setupMenus() {
        rightClickMenu = NSMenu()
        
        rightClickMenu.addItem(withTitle: "Open SyncMaven Settings", action: #selector(openSettings), keyEquivalent: ",")
        rightClickMenu.addItem(NSMenuItem.separator())
        
        let startItem = NSMenuItem(title: "Start Monitoring", action: #selector(startMonitoring), keyEquivalent: "")
        let stopItem = NSMenuItem(title: "Stop Monitoring", action: #selector(stopMonitoringAction), keyEquivalent: "")
        
        rightClickMenu.addItem(startItem)
        rightClickMenu.addItem(stopItem)
        rightClickMenu.addItem(NSMenuItem.separator())
        
        let dockItem = NSMenuItem(title: isDockIconVisible ? "Hide Dock Icon" : "Show Dock Icon", action: #selector(toggleDockIcon), keyEquivalent: "")
        dockItem.tag = 99
        rightClickMenu.addItem(dockItem)
        
        rightClickMenu.addItem(withTitle: "Quit SyncMaven", action: #selector(quit), keyEquivalent: "q")
        
        rightClickMenu.delegate = self
    }
    
    @objc private func openSettings() { showMainWindow() }
    
    @objc private func startMonitoring() {
        AppState.shared.toggleMonitoring() // Logic is inside AppState
    }
    
    @objc private func stopMonitoringAction() {
        AppState.shared.toggleMonitoring() // Logic is inside AppState
    }
    
    @objc private func toggleDockIcon() {
        isDockIconVisible.toggle()
        updateDockIconState()
    }
    
    @objc private func quit() { NSApp.terminate(nil) }
    
    private func updateDockIconState() {
        if isDockIconVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
        
        if isDockIconVisible {
            // Need to run async to allow policy change to settle
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    // ----------------------------------------------------------
    // MARK: SYNC EVENTS
    // ----------------------------------------------------------
    private func setupSyncListeners() {
        NotificationCenter.default.addObserver(self, selector: #selector(startSync), name: Notification.Name("SyncMaven.SyncStarted"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopSync), name: Notification.Name("SyncMaven.SyncFinished"), object: nil)
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
            self.updateIcon()
        }
    }

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
        guard isSyncing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.glow.toggle()
            self.updateIcon()
            if self.isSyncing { self.animateGlow() }
        }
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let isMon = AppState.shared.isMonitoring
        
        if let startItem = menu.item(withTitle: "Start Monitoring") {
            startItem.isHidden = isMon
        }
        if let stopItem = menu.item(withTitle: "Stop Monitoring") {
            stopItem.isHidden = !isMon
        }
        
        if let dockItem = menu.item(withTag: 99) {
            dockItem.title = isDockIconVisible ? "Hide Dock Icon" : "Show Dock Icon"
        }
    }
}
