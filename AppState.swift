// AppState.swift
// SyncMaven
// Fixed: Removed Initialization Cycle

import Foundation
import Combine
import AppKit
internal import SwiftUI

// Log Retention Options
enum LogRetention: Int, CaseIterable, Identifiable, Codable {
    case oneHundred = 100
    case twoHundred = 200
    case fiveHundred = 500
    case oneThousand = 1000
    case twoThousand = 2000
    case all = -1
    
    var id: Int { self.rawValue }
    var displayName: String { self == .all ? "All" : "\(self.rawValue)" }
}

final class AppState: ObservableObject {
    static let shared = AppState()
    
    private init() {
        // 1. Load Log Preference
        if let savedLimit = UserDefaults.standard.value(forKey: logLimitKey) as? Int,
           let retention = LogRetention(rawValue: savedLimit) {
            self.logRetentionLimit = retention
        }
        
        // 2. Load Data ONLY (Do not start SyncManager yet)
        loadFolders()
        repairFolderAccountIDs()
    }

    @Published var watchedFolders: [WatchedFolder] = []
    @Published var logs: [(id: UUID, text: String)] = []
    @Published var isMonitoring = false
    @Published var monitoringStartTime: Date?
    
    @Published var logRetentionLimit: LogRetention = .twoHundred {
        didSet {
            UserDefaults.standard.set(logRetentionLimit.rawValue, forKey: logLimitKey)
            trimLogs()
        }
    }

    private let foldersKey = "SyncMaven.WatchedFolders"
    private let logLimitKey = "SyncMaven.LogRetentionLimit"

    // MARK: - Startup Logic (Call this from MenuBarController)
    func restoreMonitoring() {
        // This is safe to call because 'init' is finished
        var activeCount = 0
        for folder in watchedFolders {
            if folder.enabled {
                // Verify access again before starting
                if let url = URL(string: "file://\(folder.localPath)"),
                   SecurityBookmark.startAccessing(url: url) {
                    SyncManager.shared.startMonitoring(folder)
                    activeCount += 1
                }
            }
        }
        
        if activeCount > 0 {
            isMonitoring = true
            monitoringStartTime = Date()
            log("Restored monitoring for \(activeCount) folders")
        }
    }

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

            let newFolder = WatchedFolder(localPath: url.path, bookmarkData: bookmark)
            watchedFolders.append(newFolder)
            saveFolders()
            
            // If global monitoring is on, start this one immediately
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
    
    // MARK: - Persistence & Repair
    func repairFolderAccountIDs() {
        let validIDs = AccountManager.shared.accounts.map { $0.id }
        var changed = false
        for i in watchedFolders.indices {
            let currentID = watchedFolders[i].accountID ?? ""
            if !validIDs.contains(currentID) {
                // Don't log via AppState.log() here to avoid recursion risk during init
                NSLog("[AppState] Fixing folder \(watchedFolders[i].localPath) accountID")
                watchedFolders[i].accountID = validIDs.first ?? ""
                changed = true
            }
        }
        if changed { saveFolders() }
    }

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
            self.watchedFolders = try JSONDecoder().decode([WatchedFolder].self, from: data)
            
            // Just restore bookmark access, DO NOT start SyncManager here
            for folder in watchedFolders {
                if let bookmarkData = folder.bookmarkData,
                   let url = SecurityBookmark.restoreURL(from: bookmarkData) {
                    _ = SecurityBookmark.startAccessing(url: url)
                }
            }
        } catch {
            print("Error loading folders: \(error)")
        }
    }

    // MARK: - Logging
    func log(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            let line = "[\(timestamp)] \(message)"
            self.logs.insert((UUID(), line), at: 0)
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
