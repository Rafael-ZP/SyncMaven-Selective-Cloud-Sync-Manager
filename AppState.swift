// AppState.swift
// Sinclo
// Modified to persist and autosave watched folders & Manage Log Retention

import Foundation
import Combine
import AppKit
internal import SwiftUI

// 1. New Enum for Log Retention Options
enum LogRetention: Int, CaseIterable, Identifiable, Codable {
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case oneThousand = 1000
    case twoThousand = 2000
    case all = -1 // -1 represents "All"
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        return self == .all ? "All" : "\(self.rawValue)"
    }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    
    private init() {
        // Load Log Preference
        if let savedLimit = UserDefaults.standard.value(forKey: logLimitKey) as? Int,
           let retention = LogRetention(rawValue: savedLimit) {
            self.logRetentionLimit = retention
        }
        
        loadFolders()
        repairFolderAccountIDs()
    }

    @Published var watchedFolders: [WatchedFolder] = []
    @Published var logs: [(id: UUID, text: String)] = []
    @Published var isMonitoring = false
    @Published var monitoringStartTime: Date?
    
    // 2. Published property for Log Limit
    @Published var logRetentionLimit: LogRetention = .twoHundred {
        didSet {
            UserDefaults.standard.set(logRetentionLimit.rawValue, forKey: logLimitKey)
            trimLogs() // Trim immediately if user lowers the limit
        }
    }

    private let foldersKey = "Sinclo.WatchedFolders"
    private let logLimitKey = "Sinclo.LogRetentionLimit"

    // MARK: - Folder Management
    func pickLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to watch for new files."

        if panel.runModal() == .OK, let url = panel.url {
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
            log("Monitoring started")
        } else {
            monitoringStartTime = nil
            for folder in watchedFolders {
                SyncManager.shared.stopMonitoring(folder: folder)
            }
            // 3. Log when monitoring stops
            log("Monitoring stopped")
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
    
    // MARK: - Safe Repair Function
    func repairFolderAccountIDs() {
        let validIDs = AccountManager.shared.accounts.map { $0.id }

        for i in watchedFolders.indices {
            let currentID = watchedFolders[i].accountID ?? ""
            
            if !validIDs.contains(currentID) {
                NSLog("[Fix] folder '\(watchedFolders[i].localPath)' had invalid accountID '\(String(describing: watchedFolders[i].accountID))'. Resetting.")
                watchedFolders[i].accountID = validIDs.first ?? ""
            }
        }

        saveFolders()
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
            let line = "[\(timestamp)] \(message)"
            
            // Insert new log
            self.logs.insert((UUID(), line), at: 0)

            // 4. Respect the retention limit
            self.trimLogs()
        }
    }
    
    private func trimLogs() {
        if logRetentionLimit != .all {
            if logs.count > logRetentionLimit.rawValue {
                logs = Array(logs.prefix(logRetentionLimit.rawValue))
            }
        }
    }
}
