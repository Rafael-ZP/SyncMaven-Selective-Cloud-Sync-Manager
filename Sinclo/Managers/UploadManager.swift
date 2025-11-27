//
//  UploadState.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


// UploadManager.swift
// Tracks upload progress + retries in-memory and exposes observable state.

import Foundation
import Combine

enum UploadState: String, Codable {
    case pending, uploading, completed, failed
}

final class UploadRecord: ObservableObject, Identifiable {
    let id: UUID
    let localURL: URL
    let folderLocalPath: String
    @Published var progress: Double // 0.0 - 1.0
    @Published var state: UploadState
    @Published var errorMessage: String?
    var attempts: Int = 0
    var parentDriveID: String?

    init(localURL: URL, folderLocalPath: String, parentDriveID: String? = nil) {
        self.id = UUID()
        self.localURL = localURL
        self.folderLocalPath = folderLocalPath
        self.progress = 0
        self.state = .pending
        self.parentDriveID = parentDriveID
    }
}

final class UploadManager: ObservableObject {
    static let shared = UploadManager()

    @Published private(set) var uploads: [UUID: UploadRecord] = [:]
    private let queue = DispatchQueue(label: "com.sinclo.uploadmanager", qos: .utility)
    private let semaphore = DispatchSemaphore(value: 2)

    private init() {}

    func startUpload(localURL: URL, folderLocalPath: String, parentDriveID: String?) -> UUID {
        let record = UploadRecord(localURL: localURL, folderLocalPath: folderLocalPath, parentDriveID: parentDriveID)
        uploads[record.id] = record
        runUpload(record)
        return record.id
    }

    private func runUpload(_ rec: UploadRecord) {
        queue.async {
            self.semaphore.wait()
            defer { self.semaphore.signal() }

            DispatchQueue.main.async {
                rec.attempts += 1
                rec.state = .uploading
                rec.progress = 0.0
            }

            guard let accountID = AccountManager.shared.accounts.first?.id else {
                DispatchQueue.main.async {
                    rec.state = .failed
                    rec.errorMessage = "No account configured for upload."
                    AppState.shared.log("Upload failed: No account configured.")
                }
                return
            }

            GoogleDriveManager.shared.upload(
                fileURL: rec.localURL,
                accountID: accountID,
                parentFolderID: rec.parentDriveID,
                progress: { progress in
                    DispatchQueue.main.async {
                        rec.progress = progress
                    }
                },
                completion: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            rec.progress = 1.0
                            rec.state = .completed
                            rec.errorMessage = nil
                            AppState.shared.log("Uploaded: \(rec.localURL.lastPathComponent)")
                        case .failure(let err):
                            rec.state = .failed
                            rec.errorMessage = err.localizedDescription
                            AppState.shared.log("Upload failed (\(rec.localURL.lastPathComponent)): \(err.localizedDescription)")
                        }
                    }
                }
            )
        }
    }

    func retry(recordID: UUID) {
        guard let rec = uploads[recordID] else { return }
        rec.errorMessage = nil
        rec.progress = 0
        rec.state = .pending
        runUpload(rec)
    }

    func remove(recordID: UUID) {
        uploads.removeValue(forKey: recordID)
    }

    func uploadsForFolder(path: String) -> [UploadRecord] {
        return uploads.values.filter { $0.folderLocalPath == path }.sorted { $0.state.rawValue < $1.state.rawValue }
    }
}