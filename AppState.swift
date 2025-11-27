// AppState.swift
// Sinclo
// Modified to persist and autosave watched folders

import Foundation
import Combine
import AppKit
internal import SwiftUI

final class AppState: ObservableObject {
    static let shared = AppState()
    private init() {
        loadFolders()
        // The SyncManager is now started after folders are loaded and accessed
    }

    @Published var watchedFolders: [WatchedFolder] = []
    @Published var logs: [String] = []
    @Published var isMonitoring = false
    @Published var monitoringStartTime: Date?

    private let foldersKey = "Sinclo.WatchedFolders"

    // MARK: - Folder Management
    func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to watch for new files."

        if panel.runModal() == .OK, let url = panel.url {
            // Store bookmark data
            guard let bookmark = SecurityBookmark.createBookmark(for: url) else {
                log("Failed to create security bookmark for \(url.path)")
                return
            }

            let newFolder = WatchedFolder(
                localPath: url.path,
                bookmarkData: bookmark
            )

            watchedFolders.append(newFolder)
            saveFolders()
            
            if isMonitoring {
                if SecurityBookmark.startAccessing(url: url) {
                    SyncManager.shared.startMonitoring(newFolder)
                    log("Started watching: \(url.path)")
                } else {
                    log("Failed to gain access to \(url.path)")
                }
            }
        }
    }

    func toggleMonitoring() {
        isMonitoring.toggle()
        if isMonitoring {
            monitoringStartTime = Date()
            SyncManager.shared.startMonitoringAll()
        } else {
            monitoringStartTime = nil
            for folder in watchedFolders {
                SyncManager.shared.stopMonitoring(folder: folder)
            }
        }
    }

    func removeFolders(at offsets: IndexSet) {
        let foldersToRemove = offsets.map { watchedFolders[$0] }
        for folder in foldersToRemove {
            if let url = URL(string: "file://\(folder.localPath)") {
                SecurityBookmark.stopAccessing(url: url)
            }
            SyncManager.shared.stopMonitoring(folder: folder)
        }
        watchedFolders.remove(atOffsets: offsets)
        saveFolders()
    }

    func updateFolder(_ folder: WatchedFolder) {
        if let idx = watchedFolders.firstIndex(where: { $0.id == folder.id }) {
            watchedFolders[idx] = folder
            saveFolders()
        }
    }

    // MARK: - Persistence
    private func saveFolders() {
        do {
            let data = try JSONEncoder().encode(watchedFolders)
            UserDefaults.standard.set(data, forKey: foldersKey)
        } catch {
            log("Error saving folders: \(error.localizedDescription)")
        }
    }

    private func loadFolders() {
        
        guard let data = UserDefaults.standard.data(forKey: foldersKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([WatchedFolder].self, from: data)
            self.watchedFolders = decoded
            
            // Restore access using bookmarks
            for folder in watchedFolders {
                guard let bookmarkData = folder.bookmarkData else {
                    log("No bookmark data for \(folder.localPath)")
                    continue
                }
                
                if let url = SecurityBookmark.restoreURL(from: bookmarkData) {
                    if SecurityBookmark.startAccessing(url: url) {
                        if folder.enabled {
                            SyncManager.shared.startMonitoring(folder)
                        }
                    } else {
                        log("Failed to restore access to \(url.path)")
                    }
                }
            }
        } catch {
            log("Error loading folders: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging
    func log(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            self.logs.insert("[\(timestamp)] \(message)", at: 0)
            if self.logs.count > 200 {
                self.logs.removeLast()
            }
        }
    }
    
}
