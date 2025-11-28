import Foundation
import Combine

final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    private let syncQueue = DispatchQueue(label: "com.SyncMaven.syncQueue", qos: .utility)
    private let fileOperationSemaphore = DispatchSemaphore(value: 4)
    private let fileOperationQueue = DispatchQueue(label: "com.SyncMaven.fileOps", attributes: .concurrent)
    
    private var monitors: [UUID: FolderMonitor] = [:]
    private var debounceTimers: [UUID: Timer] = [:]
    private var isSyncingMap: [UUID: Bool] = [:]
    private var cloudPollTimer: Timer?

    private init() {
        cloudPollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pollAllFolders()
        }
    }

    // MARK: - Lifecycle
    func startMonitoringAll() {
        for folder in AppState.shared.watchedFolders where folder.enabled { startMonitoring(folder) }
    }

    func startMonitoring(_ folder: WatchedFolder) {
        guard let url = URL(string: "file://\(folder.localPath)"), SecurityBookmark.startAccessing(url: url) else { return }
        
        let monitor = FolderMonitor(path: folder.localPath) { [weak self] in
            self?.triggerDebouncedSync(for: folder)
        }
        monitor.start()
        monitors[folder.id] = monitor
        
        AppState.shared.log("👀 Watching: \(folder.localPath)")
        triggerSync(for: folder)
    }

    func stopMonitoring(folder: WatchedFolder) {
        monitors[folder.id]?.stop()
        monitors.removeValue(forKey: folder.id)
        if let url = URL(string: "file://\(folder.localPath)") { SecurityBookmark.stopAccessing(url: url) }
    }

    // MARK: - Trigger Logic
    private func pollAllFolders() {
        for folder in AppState.shared.watchedFolders where folder.enabled { triggerSync(for: folder) }
    }

    private func triggerDebouncedSync(for folder: WatchedFolder) {
        DispatchQueue.main.async {
            self.debounceTimers[folder.id]?.invalidate()
            self.debounceTimers[folder.id] = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.triggerSync(for: folder)
            }
        }
    }

    private func triggerSync(for folder: WatchedFolder) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isSyncingMap[folder.id] == true { return }
            self.isSyncingMap[folder.id] = true
            
            self.performTwoWaySync(folder: folder) {
                self.syncQueue.async { self.isSyncingMap[folder.id] = false }
            }
        }
    }

    // MARK: - Reconciliation (The Logic Core)
    private func performTwoWaySync(folder: WatchedFolder, completion: @escaping () -> Void) {
        guard let accountID = folder.accountID, let rootRemoteID = folder.driveFolder?.id else { completion(); return }
        let localRoot = URL(fileURLWithPath: folder.localPath)
        
        DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("SyncMaven.SyncStarted"), object: nil) }
        
        reconcileFolder(localURL: localRoot, remoteID: rootRemoteID, accountID: accountID, ruleRootFolder: folder) {
            DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("SyncMaven.SyncFinished"), object: nil) }
            completion()
        }
    }

    private func reconcileFolder(localURL: URL, remoteID: String, accountID: String, ruleRootFolder: WatchedFolder, completion: @escaping () -> Void) {
        GoogleDriveManager.shared.listChildren(folderID: remoteID, accountID: accountID) { [weak self] result in
            guard let self = self else { completion(); return }
            switch result {
            case .failure(let error):
                AppState.shared.log("❌ Error listing cloud: \(error.localizedDescription)")
                completion()
            case .success(let remoteItems):
                self.processReconciliation(localURL: localURL, remoteID: remoteID, remoteItems: remoteItems, accountID: accountID, ruleRootFolder: ruleRootFolder, completion: completion)
            }
        }
    }

    private func processReconciliation(localURL: URL, remoteID: String, remoteItems: [String: GoogleDriveManager.DriveItem], accountID: String, ruleRootFolder: WatchedFolder, completion: @escaping () -> Void) {
        
        let localFiles = getDirectLocalChildren(for: localURL)
        let localFileNames = Set(localFiles.map { $0.lastPathComponent })
        let group = DispatchGroup()
        
        // 1. ITERATE LOCAL FILES
        for localItem in localFiles {
            let name = localItem.lastPathComponent
            let relativePath = localItem.path.replacingOccurrences(of: URL(fileURLWithPath: ruleRootFolder.localPath).path + "/", with: "")
            let isDir = (try? localItem.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            
            if isDir {
                group.enter()
                if let remoteFolder = remoteItems[name], remoteFolder.isFolder {
                    // Both exist: Recurse
                    reconcileFolder(localURL: localItem, remoteID: remoteFolder.id, accountID: accountID, ruleRootFolder: ruleRootFolder) { group.leave() }
                } else {
                    // Missing Remote: Create & Recurse
                    createRemoteFolderAndSync(localURL: localItem, name: name, parentID: remoteID, accountID: accountID, ruleRootFolder: ruleRootFolder) { group.leave() }
                }
            } else {
                // FILE Handling
                // Check if missing remotely
                if remoteItems[name] == nil {
                    // LOGIC CHECK: Was it previously synced and deleted remotely?
                    if ruleRootFolder.syncedFiles[relativePath] != nil {
                        // It IS in cache, but NOT in Remote Items.
                        // Means: User deleted it from Google Drive.
                        // Action: DELETE LOCAL.
                        group.enter()
                        deleteLocalFile(localURL: localItem, ruleRootFolder: ruleRootFolder, relativePath: relativePath) { group.leave() }
                    } else {
                        // It is NOT in cache.
                        // Means: New Local File.
                        // Action: UPLOAD (If rules match)
                        if SyncManager.shared.fileMatchesRule(localItem, folder: ruleRootFolder) {
                            group.enter()
                            uploadFileConcurrent(localURL: localItem, parentID: remoteID, accountID: accountID, ruleRootFolder: ruleRootFolder) { group.leave() }
                        }
                    }
                }
            }
        }
        
        // 2. ITERATE REMOTE FILES
        for (name, remoteItem) in remoteItems {
            let localItemURL = localURL.appendingPathComponent(name)
            let relativePath = localItemURL.path.replacingOccurrences(of: URL(fileURLWithPath: ruleRootFolder.localPath).path + "/", with: "")
            
            if !localFileNames.contains(name) {
                // Missing Locally
                if ruleRootFolder.syncedFiles[relativePath] != nil {
                    // It IS in cache, but NOT in Local Files.
                    // Means: User deleted it Locally.
                    // Action: DELETE REMOTE.
                    group.enter()
                    deleteRemoteFileConcurrent(fileID: remoteItem.id, name: name, accountID: accountID, ruleRootFolder: ruleRootFolder, relativePath: relativePath) { group.leave() }
                } else {
                    // It is NOT in cache.
                    // Means: New Remote File.
                    // Action: DOWNLOAD (If rules match)
                    if !remoteItem.isFolder && !remoteItem.trashed {
                        // CHECK RULES (Size/Ext) for DOWNLOAD too
                        if downloadMatchesRule(remoteItem: remoteItem, folder: ruleRootFolder) {
                            group.enter()
                            downloadFileConcurrent(fileID: remoteItem.id, localURL: localItemURL, accountID: accountID, ruleRootFolder: ruleRootFolder, relativePath: relativePath) { group.leave() }
                        }
                    } else if remoteItem.isFolder && !remoteItem.trashed {
                        // New Remote Folder -> Create Local & Recurse
                        try? FileManager.default.createDirectory(at: localItemURL, withIntermediateDirectories: true)
                        group.enter()
                        reconcileFolder(localURL: localItemURL, remoteID: remoteItem.id, accountID: accountID, ruleRootFolder: ruleRootFolder) { group.leave() }
                    }
                }
            } else {
                // Exists in both places.
                // Just ensure it's tracked in our cache map.
                if ruleRootFolder.syncedFiles[relativePath] == nil {
                    DispatchQueue.main.async { ruleRootFolder.syncedFiles[relativePath] = remoteItem.id }
                }
            }
        }
        
        group.notify(queue: .global(qos: .utility)) {
            DispatchQueue.main.async { AppState.shared.updateFolder(ruleRootFolder) }
            completion()
        }
    }

    // MARK: - Actions

    private func createRemoteFolderAndSync(localURL: URL, name: String, parentID: String, accountID: String, ruleRootFolder: WatchedFolder, completion: @escaping () -> Void) {
        AppState.shared.log("📁 Creating Cloud Folder: \(name)")
        GoogleDriveManager.shared.createFolder(name: name, parentID: parentID, accountID: accountID) { [weak self] result in
            switch result {
            case .success(let newID):
                self?.reconcileFolder(localURL: localURL, remoteID: newID, accountID: accountID, ruleRootFolder: ruleRootFolder, completion: completion)
            case .failure:
                completion()
            }
        }
    }

    private func uploadFileConcurrent(localURL: URL, parentID: String, accountID: String, ruleRootFolder: WatchedFolder, completion: @escaping () -> Void) {
        fileOperationQueue.async { [weak self] in
            guard let self = self else { completion(); return }
            self.fileOperationSemaphore.wait()
            AppState.shared.log("⬆️ Uploading: \(localURL.lastPathComponent)")
            
            GoogleDriveManager.shared.upload(fileURL: localURL, accountID: accountID, parentFolderID: parentID, progress: { _ in }) { result in
                self.fileOperationSemaphore.signal()
                switch result {
                case .success(let fileID):
                    AppState.shared.log("✅ Finished Upload: \(localURL.lastPathComponent)")
                    let relativePath = localURL.path.replacingOccurrences(of: URL(fileURLWithPath: ruleRootFolder.localPath).path + "/", with: "")
                    DispatchQueue.main.async { ruleRootFolder.syncedFiles[relativePath] = fileID }
                case .failure(let error):
                    AppState.shared.log("❌ Upload failed: \(localURL.lastPathComponent) - \(error.localizedDescription)")
                }
                completion()
            }
        }
    }

    private func downloadFileConcurrent(fileID: String, localURL: URL, accountID: String, ruleRootFolder: WatchedFolder, relativePath: String, completion: @escaping () -> Void) {
        fileOperationQueue.async { [weak self] in
            guard let self = self else { completion(); return }
            self.fileOperationSemaphore.wait()
            AppState.shared.log("⬇️ Downloading: \(localURL.lastPathComponent)")
            
            GoogleDriveManager.shared.download(fileID: fileID, to: localURL, accountID: accountID) { error in
                self.fileOperationSemaphore.signal()
                if let error = error {
                    AppState.shared.log("❌ Download failed: \(error.localizedDescription)")
                } else {
                    AppState.shared.log("✅ Finished Download: \(localURL.lastPathComponent)")
                    DispatchQueue.main.async { ruleRootFolder.syncedFiles[relativePath] = fileID }
                }
                completion()
            }
        }
    }
    
    private func deleteRemoteFileConcurrent(fileID: String, name: String, accountID: String, ruleRootFolder: WatchedFolder, relativePath: String, completion: @escaping () -> Void) {
        fileOperationQueue.async { [weak self] in
            guard let self = self else { completion(); return }
            self.fileOperationSemaphore.wait()
            AppState.shared.log("🗑️ Deleting Remote: \(name)")
            
            GoogleDriveManager.shared.delete(fileID: fileID, accountID: accountID) { error in
                self.fileOperationSemaphore.signal()
                if error == nil {
                    AppState.shared.log("✅ Remote Deleted: \(name)")
                    DispatchQueue.main.async { ruleRootFolder.syncedFiles.removeValue(forKey: relativePath) }
                } else {
                    AppState.shared.log("❌ Remote Delete Failed: \(name)")
                }
                completion() // Ensures queue doesn't hang
            }
        }
    }
    
    private func deleteLocalFile(localURL: URL, ruleRootFolder: WatchedFolder, relativePath: String, completion: @escaping () -> Void) {
        // Local delete is fast, can run on main or utility queue, no semaphore needed
        DispatchQueue.main.async {
            do {
                try FileManager.default.removeItem(at: localURL)
                AppState.shared.log("🗑️ Deleted Local (Sync): \(localURL.lastPathComponent)")
                ruleRootFolder.syncedFiles.removeValue(forKey: relativePath)
            } catch {
                AppState.shared.log("❌ Failed to delete local: \(localURL.lastPathComponent)")
            }
            completion()
        }
    }

    // MARK: - Helper Rules
    
    private func getDirectLocalChildren(for localURL: URL) -> [URL] {
        let fm = FileManager.default
        do { return try fm.contentsOfDirectory(at: localURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) } catch { return [] }
    }

    func fileMatchesRule(_ fileURL: URL, folder: WatchedFolder) -> Bool {
        for rule in folder.rules {
            if RuleEngine.fileMatchesRule(fileURL: fileURL, rule: rule) { return true }
        }
        return false
    }
    
    // Check Rules for DOWNLOADS using the size we now fetch from API
    func downloadMatchesRule(remoteItem: GoogleDriveManager.DriveItem, folder: WatchedFolder) -> Bool {
            for rule in folder.rules {
                // 1. Check Extensions (Blacklist/Ignore logic)
                let ext = (remoteItem.name as NSString).pathExtension.lowercased()
                if rule.ignoredExtensions.contains(ext) {
                    continue
                }
                
                // 2. Check Size
                let lowerBoundBytes = rule.lowerBound * rule.unit.multiplier
                let upperBoundBytes = rule.upperBound * rule.unit.multiplier
                
                // DriveItem.size is Int64 bytes
                if UInt64(remoteItem.size) < lowerBoundBytes { continue }
                if UInt64(remoteItem.size) > upperBoundBytes { continue }
                
                return true // Matches a rule
            }
            return false // Matches no rules
        }
}
