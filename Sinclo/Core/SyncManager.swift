import Foundation
import AppKit
import UserNotifications
import Combine

final class SyncManager: ObservableObject {

    static let shared = SyncManager()

    private var monitors: [UUID: FolderMonitor] = [:]
    private let uploadQueue = DispatchQueue(label: "com.sinclo.uploadQueue", qos: .utility)
    private let semaphore = DispatchSemaphore(value: 2)

    private init() {}

    // MARK: Start monitoring
    func startMonitoringAll() {
        for folder in AppState.shared.watchedFolders {
            startMonitoring(folder)
        }
    }

    func startMonitoring(_ folder: WatchedFolder) {
        let path = folder.localPath
        let monitor = FolderMonitor(path: path) { [weak self] in
            self?.handleFolderChange(folder)
        }
        monitor.start()
        monitors[folder.id] = monitor

        AppState.shared.log("Started monitoring: \(path)")
    }

    // MARK: Folder change handler
    func handleFolderChange(_ folder: WatchedFolder) {
        let url = URL(fileURLWithPath: folder.localPath)
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(at: url,
                                                      includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                                                      options: [.skipsHiddenFiles])
        else { return }

        for item in items {
            if fileMatchesRule(item, folder: folder) {
                enqueueUpload(item)
            }
        }
    }

    // MARK: Rule checking (simple: max file size)
    func fileMatchesRule(_ fileURL: URL, folder: WatchedFolder) -> Bool {
        let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard let isDir = res?.isDirectory, isDir == false else { return false }

        if let size = res?.fileSize {
            let sizeMB = size / (1024 * 1024)
            if sizeMB <= folder.maxSizeMB {
                return true
            }
        }
        return false
    }

    // MARK: Upload queue
    func enqueueUpload(_ localURL: URL) {
        uploadQueue.async {
            self.semaphore.wait()
            defer { self.semaphore.signal() }

            guard let folderID = AppState.shared.watchedFolders.first(where: {
                localURL.path.hasPrefix($0.localPath)
            })?.driveFolder?.id else {
                print("No drive folder selected")
                return
            }

            GoogleDriveManager.shared.upload(fileURL: localURL, parentFolderID: folderID) { result in
                switch result {
                case .success:
                    AppState.shared.log("Uploaded: \(localURL.lastPathComponent)")
                case .failure(let e):
                    AppState.shared.log("Upload failed: \(e.localizedDescription)")
                }
            }
        }
    }
}
