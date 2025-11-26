// AppState.swift
// Sinclo
// Modified to persist and autosave watched folders

import Combine
import Foundation
import SwiftUI
import AppKit

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var watchedFolders: [WatchedFolder] = [] {
        didSet { Persistence.shared.saveWatchedFolders(watchedFolders) }
    }
    @Published var logs: [String] = [] {
        didSet {
            // keep last 500 only
            if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        }
    }

    private init() {
        // restore persisted folders at startup
        self.watchedFolders = Persistence.shared.loadWatchedFolders()
        log("App started — loaded \(watchedFolders.count) watched folders")
    }

    // Add a folder manually
    func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose a Folder to Sync"

        if panel.runModal() == .OK {
            if let url = panel.url {
                let folder = WatchedFolder(path: url.path)
                watchedFolders.append(folder)
                log("Added folder: \(url.path)")

                // Start monitoring immediately
                SyncManager.shared.startMonitoring(folder)
            }
        }
    }

    func removeFolders(at offsets: IndexSet) {
        for i in offsets {
            let f = watchedFolders[i]
            log("Removed folder: \(f.localPath)")
            // stop monitor if running
            SyncManager.shared.stopMonitoring(folder: f)
        }
        watchedFolders.remove(atOffsets: offsets)
        // Persistence happens via didSet
    }

    func updateFolder(_ folder: WatchedFolder) {
        // Ensure persistence triggered by replacing the item in array
        if let idx = watchedFolders.firstIndex(where: { $0.id == folder.id }) {
            watchedFolders[idx] = folder
            log("Updated folder: \(folder.localPath)")
        } else {
            // if not present, add
            watchedFolders.append(folder)
            log("Added folder via update: \(folder.localPath)")
            SyncManager.shared.startMonitoring(folder)
        }
    }

    func log(_ text: String) {
        DispatchQueue.main.async {
            self.logs.append("[\(self.timestamp())] \(text)")
        }
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
