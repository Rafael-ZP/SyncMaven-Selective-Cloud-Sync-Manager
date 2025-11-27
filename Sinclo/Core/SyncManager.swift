import Foundation
import AppKit
import UserNotifications
import Combine

final class SyncManager: ObservableObject {

    static let shared = SyncManager()

    private var monitors: [UUID: FolderMonitor] = [:]
    private let uploadQueue = DispatchQueue(label: "com.sinclo.uploadQueue", qos: .utility)
    private let semaphore = DispatchSemaphore(value: 2)
    private var inProgressUploads = Set<URL>()
    private let inProgressQueue = DispatchQueue(label: "com.sinclo.inProgressQueue")

    private init() {}

    // MARK: Start monitoring
    func startMonitoringAll() {
        for folder in AppState.shared.watchedFolders {
            if folder.enabled {
                startMonitoring(folder)
            }
        }
    }

    func startMonitoring(_ folder: WatchedFolder) {
        guard let url = URL(string: "file://\(folder.localPath)"),
              SecurityBookmark.startAccessing(url: url) else {
            AppState.shared.log("Failed to access \(folder.localPath) for monitoring.")
            return
        }
        
        let monitor = FolderMonitor(path: folder.localPath) { [weak self] in
            self?.handleFolderChange(folder)
        }
        monitor.start()
        monitors[folder.id] = monitor

        AppState.shared.log("Started monitoring: \(folder.localPath)")
    }

    // MARK: Folder change handler
    func handleFolderChange(_ folder: WatchedFolder) {
        guard let accountID = folder.accountID, let driveFolderID = folder.driveFolder?.id else {
            AppState.shared.log("Folder \(folder.localPath) is not configured with a Google Account and Drive folder.")
            return
        }

        let localFiles = getLocalFiles(for: folder)
        
        GoogleDriveManager.shared.listChildren(folderID: driveFolderID, accountID: accountID) { result in
            switch result {
            case .success(let remoteFiles):
                let localFileNames = Set(localFiles.map { $0.lastPathComponent })
                let remoteFileNames = Set(remoteFiles.keys)
                
                // Upload new files to cloud
                for fileURL in localFiles {
                    if !remoteFileNames.contains(fileURL.lastPathComponent) {
                        AppState.shared.log("Uploading \(fileURL.lastPathComponent) to \(folder.driveFolderName ?? "Drive")")
                        self.enqueueUpload(fileURL, folder: folder)
                    }
                }
                
                // Download new files from cloud
                for (fileName, fileID) in remoteFiles {
                    if !localFileNames.contains(fileName) {
                        let localURL = URL(fileURLWithPath: folder.localPath).appendingPathComponent(fileName)
                        GoogleDriveManager.shared.download(fileID: fileID, to: localURL, accountID: accountID) { error in
                            if let error = error {
                                AppState.shared.log("Failed to download \(fileName): \(error.localizedDescription)")
                            } else {
                                AppState.shared.log("Downloaded \(fileName) from cloud.")
                                DispatchQueue.main.async {
                                    folder.syncedFiles[fileName] = fileID
                                }
                            }
                        }
                    }
                }
                
                // To handle deletions, we need to compare the current state with a previous state.
                // This is a complex feature that requires a persistent state store.
                // For now, we will only handle additions.
                
            case .failure(let error):
                AppState.shared.log("Failed to list remote files: \(error.localizedDescription)")
            }
        }
    }

    private func getLocalFiles(for folder: WatchedFolder) -> [URL] {
        let url = URL(fileURLWithPath: folder.localPath)
        let fm = FileManager.default
        var files: [URL] = []

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return files
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues.isRegularFile! {
                    if fileMatchesRule(fileURL, folder: folder) {
                        files.append(fileURL)
                    }
                }
            } catch {
                AppState.shared.log("Error processing file \(fileURL.path): \(error)")
            }
        }
        return files
    }

    // MARK: Rule checking
    func fileMatchesRule(_ fileURL: URL, folder: WatchedFolder) -> Bool {
        for rule in folder.rules {
            if RuleEngine.fileMatchesRule(fileURL: fileURL, rule: rule) {
                return true
            }
        }
        return false
    }
    
    func stopMonitoring(folder: WatchedFolder) {
        if let m = monitors[folder.id] {
            m.stop()
            monitors.removeValue(forKey: folder.id)
            if let url = URL(string: "file://\(folder.localPath)") {
                SecurityBookmark.stopAccessing(url: url)
            }
            AppState.shared.log("Stopped monitoring: \(folder.localPath)")
        }
    }
    
    // MARK: Upload queue
    func enqueueUpload(_ localURL: URL, folder: WatchedFolder) {
        uploadQueue.async {
            self.semaphore.wait()
            
            NotificationCenter.default.post(name: Notification.Name("Sinclo.SyncStarted"), object: nil)
            
            defer {
                self.semaphore.signal()
                self.inProgressQueue.sync {
                    self.inProgressUploads.remove(localURL)
                }
                NotificationCenter.default.post(name: Notification.Name("Sinclo.SyncFinished"), object: nil)
            }

            guard let accountID = folder.accountID else {
                AppState.shared.log("No account configured for folder \(folder.localPath).")
                return
            }
            
            guard let folderID = folder.driveFolder?.id else {
                AppState.shared.log("No drive folder selected for \(folder.localPath)")
                return
            }

            GoogleDriveManager.shared.upload(
                fileURL: localURL,
                accountID: accountID,
                parentFolderID: folderID,
                progress: { _ in },
                completion: { result in
                    switch result {
                    case .success(let fileID):
                        DispatchQueue.main.async {
                            folder.syncedFiles[localURL.lastPathComponent] = fileID
                            AppState.shared.updateFolder(folder)
                        }
                        AppState.shared.log("Uploaded: \(localURL.lastPathComponent)")
                    case .failure(let e):
                        AppState.shared.log("Upload failed for \(localURL.lastPathComponent): \(e.localizedDescription)")
                    }
                }
            )
        }
    }
    
}
