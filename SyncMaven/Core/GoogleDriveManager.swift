import Foundation

final class GoogleDriveManager: NSObject {
    static let shared = GoogleDriveManager()
    
    private let baseURL = "https://www.googleapis.com/drive/v3"
    private let uploadURL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"
    
    private var metadataSession: URLSession!
    private var uploadSession: URLSession!
    
    private var uploadTasks: [Int: ResumableUploadTask] = [:]
    private let stateQueue = DispatchQueue(label: "com.SyncMaven.driveState")

    private override init() {
        super.init()
        
        let metaConfig = URLSessionConfiguration.default
        metaConfig.timeoutIntervalForRequest = 30
        metaConfig.httpMaximumConnectionsPerHost = 6
        self.metadataSession = URLSession(configuration: metaConfig, delegate: nil, delegateQueue: nil)
        
        let uploadConfig = URLSessionConfiguration.default
        uploadConfig.timeoutIntervalForRequest = 300
        uploadConfig.timeoutIntervalForResource = 14400
        uploadConfig.httpMaximumConnectionsPerHost = 4
        self.uploadSession = URLSession(configuration: uploadConfig, delegate: self, delegateQueue: nil)
    }

    // UPDATED: Added 'size' to struct
    struct DriveItem {
        let id: String
        let name: String
        let isFolder: Bool
        let mimeType: String
        let trashed: Bool
        let size: Int64 // Bytes
    }

    // MARK: - Metadata Operations

    func listChildren(folderID: String, accountID: String, completion: @escaping (Result<[String: DriveItem], Error>) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let token):
                var components = URLComponents(string: "\(self.baseURL)/files")!
                components.queryItems = [
                    URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
                    // UPDATED: Request 'size' field
                    URLQueryItem(name: "fields", value: "files(id, name, mimeType, trashed, size)"),
                    URLQueryItem(name: "pageSize", value: "1000")
                ]
                
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                self.metadataSession.dataTask(with: request) { data, _, error in
                    if let error = error { completion(.failure(error)); return }
                    guard let data = data else { completion(.failure(NSError(domain: "GDrive", code: 404, userInfo: nil))); return }
                    
                    do {
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        let files = (json?["files"] as? [[String: Any]]) ?? []
                        var itemsDict: [String: DriveItem] = [:]
                        
                        for file in files {
                            if let id = file["id"] as? String,
                               let name = file["name"] as? String,
                               let mime = file["mimeType"] as? String {
                                
                                let trashed = file["trashed"] as? Bool ?? false
                                // Parse size (comes as String from API)
                                let sizeStr = file["size"] as? String ?? "0"
                                let size = Int64(sizeStr) ?? 0
                                
                                itemsDict[name] = DriveItem(
                                    id: id,
                                    name: name,
                                    isFolder: (mime == "application/vnd.google-apps.folder"),
                                    mimeType: mime,
                                    trashed: trashed,
                                    size: size
                                )
                            }
                        }
                        completion(.success(itemsDict))
                    } catch { completion(.failure(error)) }
                }.resume()
            }
        }
    }

    func createFolder(name: String, parentID: String, accountID: String, completion: @escaping (Result<String, Error>) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let token):
                var request = URLRequest(url: URL(string: "\(self.baseURL)/files")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body: [String: Any] = ["name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parentID]]
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                
                self.metadataSession.dataTask(with: request) { data, _, error in
                    if let error = error { completion(.failure(error)); return }
                    guard let data = data,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = json["id"] as? String else {
                        completion(.failure(NSError(domain: "GDrive", code: 502, userInfo: nil)))
                        return
                    }
                    completion(.success(id))
                }.resume()
            }
        }
    }
    
    func delete(fileID: String, accountID: String, completion: @escaping (Error?) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let e): completion(e)
            case .success(let token):
                var request = URLRequest(url: URL(string: "\(self.baseURL)/files/\(fileID)")!)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                self.metadataSession.dataTask(with: request) { _, _, err in completion(err) }.resume()
            }
        }
    }

    // MARK: - Upload Operations (Instrumented)

    func upload(fileURL: URL, accountID: String, parentFolderID: String?, progress: @escaping (Double) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
        let fileName = fileURL.lastPathComponent
        print("🚀 [GDrive] Request to upload: \(fileName)")
        
        let task = ResumableUploadTask(fileURL: fileURL, accountID: accountID, parentFolderID: parentFolderID, progress: progress, completion: completion)
        
        let startTime = Date()
        withValidAccessToken(accountID: accountID) { result in
            let duration = Date().timeIntervalSince(startTime)
            print("🔑 [GDrive] Token fetch took: \(String(format: "%.3f", duration))s")
            
            switch result {
            case .failure(let error):
                print("❌ [GDrive] Token failed: \(error)")
                completion(.failure(error))
            case .success(let token):
                self.startResumableUpload(token: token, task: task)
            }
        }
    }

    private func startResumableUpload(token: String, task: ResumableUploadTask) {
        print("📡 [GDrive] Starting Resumable Handshake (POST) for \(task.fileURL.lastPathComponent)")
        
        var request = URLRequest(url: URL(string: self.uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: task.fileURL.path),
           let size = attrs[.size] as? UInt64 {
            request.setValue("\(size)", forHTTPHeaderField: "X-Upload-Content-Length")
        }

        let metadata: [String: Any] = [
            "name": task.fileURL.lastPathComponent,
            "parents": task.parentFolderID != nil ? [task.parentFolderID!] : []
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: metadata)

        let handshakeStart = Date()
        
        // Use uploadSession for handshake to prevent metadata queue blocking
        let sessionTask = self.uploadSession.dataTask(with: request) { [weak self] _, response, error in
            let duration = Date().timeIntervalSince(handshakeStart)
            print("📡 [GDrive] Handshake response received in: \(String(format: "%.3f", duration))s")
            
            if let error = error {
                print("❌ [GDrive] Handshake Error: \(error)")
                task.completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let location = httpResponse.allHeaderFields["Location"] as? String,
               let sessionURI = URL(string: location) {
                
                print("✅ [GDrive] Session URI obtained. Starting PUT.")
                task.uploadSessionURI = sessionURI
                self?.executeUploadPut(task: task)
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                print("❌ [GDrive] Handshake failed. Code: \(code)")
                task.completion(.failure(NSError(domain: "GDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initiate upload session"])))
            }
        }
        sessionTask.resume()
    }

    private func executeUploadPut(task: ResumableUploadTask) {
        guard let uri = task.uploadSessionURI else { return }
        var request = URLRequest(url: uri)
        request.httpMethod = "PUT"
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: task.fileURL.path),
           let fileSize = attrs[.size] as? UInt64 {
            request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
            print("📦 [GDrive] Uploading \(fileSize) bytes for \(task.fileURL.lastPathComponent)")
        }
        
        let uploadTask = self.uploadSession.uploadTask(with: request, fromFile: task.fileURL)
        
        stateQueue.async {
            self.uploadTasks[uploadTask.taskIdentifier] = task
        }
        
        uploadTask.resume()
    }

    func download(fileID: String, to localUrl: URL, accountID: String, completion: @escaping (Error?) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error): completion(error)
            case .success(let token):
                let url = URL(string: "\(self.baseURL)/files/\(fileID)?alt=media")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                self.uploadSession.downloadTask(with: request) { tempUrl, _, error in
                    if let error = error { completion(error); return }
                    guard let tempUrl = tempUrl else { completion(NSError(domain: "GDrive", code: 501, userInfo: nil)); return }
                    do {
                        if FileManager.default.fileExists(atPath: localUrl.path) {
                            try FileManager.default.removeItem(at: localUrl)
                        }
                        try FileManager.default.createDirectory(at: localUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: tempUrl, to: localUrl)
                        completion(nil)
                    } catch { completion(error) }
                }.resume()
            }
        }
    }

    // MARK: - Helpers
    private func withValidAccessToken(accountID: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let (token, _) = AccountManager.shared.tokens(for: accountID) else {
            completion(.failure(NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "No token found"])))
            return
        }
        completion(.success(token))
    }
    
    private class ResumableUploadTask {
        let fileURL: URL
        let accountID: String
        let parentFolderID: String?
        let completion: (Result<String, Error>) -> Void
        let progress: (Double) -> Void
        var uploadSessionURI: URL?
        var lastProgressPrintTime: Date = Date() // Limit print spam

        init(fileURL: URL, accountID: String, parentFolderID: String?, progress: @escaping (Double) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
            self.fileURL = fileURL
            self.accountID = accountID
            self.parentFolderID = parentFolderID
            self.progress = progress
            self.completion = completion
        }
    }
}

// MARK: - Delegates
extension GoogleDriveManager: URLSessionDataDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        stateQueue.async {
            guard let task = self.uploadTasks[dataTask.taskIdentifier] else { return }
            print("✅ [GDrive] Received Final JSON Response for \(task.fileURL.lastPathComponent)")
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? String {
                task.completion(.success(id))
                self.uploadTasks.removeValue(forKey: dataTask.taskIdentifier)
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        stateQueue.async {
            if let uploadTask = self.uploadTasks[task.taskIdentifier] {
                let pct = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
                uploadTask.progress(pct)
                
                // Print progress every 1 second to avoid spamming console
                if Date().timeIntervalSince(uploadTask.lastProgressPrintTime) > 1.0 {
                    print("⏳ [GDrive] Progress: \(Int(pct * 100))% for \(uploadTask.fileURL.lastPathComponent)")
                    uploadTask.lastProgressPrintTime = Date()
                }
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            if let error = error, let uploadTask = self.uploadTasks[task.taskIdentifier] {
                print("❌ [GDrive] Session Task Failed: \(error.localizedDescription)")
                uploadTask.completion(.failure(error))
                self.uploadTasks.removeValue(forKey: task.taskIdentifier)
            }
        }
    }
}

// MARK: - Drive Picker Helper
extension GoogleDriveManager {
    func listAllFolders(accountID: String, completion: @escaping (Result<[DriveFolder], Error>) -> Void) {
            print("📂 [GDrive] Requesting Folders for Account: \(accountID)")
            
            withValidAccessToken(accountID: accountID) { result in
                switch result {
                case .failure(let error):
                    print("❌ [GDrive] Folder List Token Error: \(error)")
                    completion(.failure(error))
                    
                case .success(let token):
                    print("🔑 [GDrive] Token valid. Building URL...")
                    
                    var components = URLComponents(string: "\(self.baseURL)/files")!
                    components.queryItems = [
                        URLQueryItem(name: "q", value: "mimeType='application/vnd.google-apps.folder' and trashed=false"),
                        URLQueryItem(name: "fields", value: "files(id, name)"),
                        URLQueryItem(name: "pageSize", value: "1000")
                    ]
                    
                    guard let url = components.url else {
                        completion(.failure(NSError(domain: "GDrive", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    // FORCE TIMEOUT: If it takes longer than 15s, fail.
                    request.timeoutInterval = 15
                    
                    print("📡 [GDrive] Sending Folder List Request...")
                    
                    self.metadataSession.dataTask(with: request) { data, response, error in
                        if let error = error {
                            print("❌ [GDrive] Network Error: \(error.localizedDescription)")
                            completion(.failure(error))
                            return
                        }
                        
                        if let httpResponse = response as? HTTPURLResponse {
                            print("abc [GDrive] Response Code: \(httpResponse.statusCode)")
                            if !(200...299).contains(httpResponse.statusCode) {
                                print("❌ [GDrive] Server Error. Headers: \(httpResponse.allHeaderFields)")
                            }
                        }
                        
                        guard let data = data else {
                            print("❌ [GDrive] No Data Received")
                            completion(.failure(NSError(domain: "GDrive", code: 404, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                            return
                        }
                        
                        do {
                            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                            let files = (json?["files"] as? [[String: Any]]) ?? []
                            
                            print("✅ [GDrive] Found \(files.count) folders.")
                            
                            let mappedFolders = files.compactMap { file -> DriveFolder? in
                                guard let id = file["id"] as? String,
                                      let name = file["name"] as? String else { return nil }
                                return DriveFolder(id: id, name: name)
                            }
                            
                            completion(.success(mappedFolders))
                        } catch {
                            print("❌ [GDrive] JSON Parse Error: \(error)")
                            completion(.failure(error))
                        }
                    }.resume()
                }
            }
        }
}
