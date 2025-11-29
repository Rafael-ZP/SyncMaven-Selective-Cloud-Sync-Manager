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

    struct DriveItem {
        let id: String
        let name: String
        let isFolder: Bool
        let mimeType: String
        let trashed: Bool
        let size: Int64
    }

    // MARK: - Metadata Operations

    // FIXED: Now handles Pagination (nextPageToken) to ensure we see ALL files
    func listChildren(folderID: String, accountID: String, completion: @escaping (Result<[String: DriveItem], Error>) -> Void) {
        
        var allItems: [String: DriveItem] = [:]
        
        // Recursive function to fetch pages
        func fetchPage(pageToken: String?) {
            withValidAccessToken(accountID: accountID) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .failure(let error):
                    completion(.failure(error))
                    
                case .success(let token):
                    var components = URLComponents(string: "\(self.baseURL)/files")!
                    var queryItems = [
                        URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
                        URLQueryItem(name: "fields", value: "nextPageToken, files(id, name, mimeType, trashed, size)"),
                        URLQueryItem(name: "pageSize", value: "1000")
                    ]
                    
                    if let pageToken = pageToken {
                        queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
                    }
                    components.queryItems = queryItems
                    
                    var request = URLRequest(url: components.url!)
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    
                    self.metadataSession.dataTask(with: request) { data, _, error in
                        if let error = error { completion(.failure(error)); return }
                        guard let data = data else { completion(.failure(NSError(domain: "GDrive", code: 404, userInfo: nil))); return }
                        
                        do {
                            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                            let files = (json?["files"] as? [[String: Any]]) ?? []
                            
                            // Process current page
                            for file in files {
                                if let id = file["id"] as? String,
                                   let name = file["name"] as? String,
                                   let mime = file["mimeType"] as? String {
                                    
                                    let trashed = file["trashed"] as? Bool ?? false
                                    let sizeStr = file["size"] as? String ?? "0"
                                    let size = Int64(sizeStr) ?? 0
                                    
                                    // Logic: If duplicate names exist, keep the Folder over the File, or the newest one
                                    // For now, simple overwrite is standard for map-based sync
                                    allItems[name] = DriveItem(
                                        id: id,
                                        name: name,
                                        isFolder: (mime == "application/vnd.google-apps.folder"),
                                        mimeType: mime,
                                        trashed: trashed,
                                        size: size
                                    )
                                }
                            }
                            
                            // Check if there is another page
                            if let nextToken = json?["nextPageToken"] as? String {
                                fetchPage(pageToken: nextToken) // Recurse
                            } else {
                                completion(.success(allItems)) // Done
                            }
                            
                        } catch {
                            completion(.failure(error))
                        }
                    }.resume()
                }
            }
        }
        
        // Start the chain
        fetchPage(pageToken: nil)
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
                
                let body: [String: Any] = [
                    "name": name,
                    "mimeType": "application/vnd.google-apps.folder",
                    "parents": [parentID]
                ]
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

    // MARK: - Upload Operations

    func upload(fileURL: URL, accountID: String, parentFolderID: String?, progress: @escaping (Double) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
        let task = ResumableUploadTask(fileURL: fileURL, accountID: accountID, parentFolderID: parentFolderID, progress: progress, completion: completion)
        
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let token):
                self.startResumableUpload(token: token, task: task)
            }
        }
    }

    private func startResumableUpload(token: String, task: ResumableUploadTask) {
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

        self.uploadSession.dataTask(with: request) { [weak self] _, response, error in
            if let error = error { task.completion(.failure(error)); return }
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let location = httpResponse.allHeaderFields["Location"] as? String,
               let sessionURI = URL(string: location) {
                
                task.uploadSessionURI = sessionURI
                self?.executeUploadPut(task: task)
            } else {
                task.completion(.failure(NSError(domain: "GDrive", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to initiate upload session"])))
            }
        }.resume()
    }

    private func executeUploadPut(task: ResumableUploadTask) {
        guard let uri = task.uploadSessionURI else { return }
        var request = URLRequest(url: uri)
        request.httpMethod = "PUT"
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: task.fileURL.path),
           let fileSize = attrs[.size] as? UInt64 {
            request.setValue("\(fileSize)", forHTTPHeaderField: "Content-Length")
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
                
                self.uploadSession.downloadTask(with: request) { tempUrl, response, error in
                    if let error = error { completion(error); return }
                    guard let tempUrl = tempUrl else { completion(NSError(domain: "GDrive", code: 501, userInfo: nil)); return }
                    
                    do {
                        if FileManager.default.fileExists(atPath: localUrl.path) {
                            try FileManager.default.removeItem(at: localUrl)
                        }
                        try FileManager.default.createDirectory(at: localUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try FileManager.default.moveItem(at: tempUrl, to: localUrl)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
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
                uploadTask.progress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        stateQueue.async {
            if let error = error, let uploadTask = self.uploadTasks[task.taskIdentifier] {
                uploadTask.completion(.failure(error))
                self.uploadTasks.removeValue(forKey: task.taskIdentifier)
            }
        }
    }
}

// MARK: - Drive Picker Helper
extension GoogleDriveManager {
    func listAllFolders(accountID: String, completion: @escaping (Result<[DriveFolder], Error>) -> Void) {
        // Reuse the robust listChildren logic but mapped for the picker
        // For the picker, a flat list of 1000 is usually enough, but we use the robust session here.
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let token):
                var components = URLComponents(string: "\(self.baseURL)/files")!
                components.queryItems = [
                    URLQueryItem(name: "q", value: "mimeType='application/vnd.google-apps.folder' and trashed=false"),
                    URLQueryItem(name: "fields", value: "files(id, name)"),
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
                        let mappedFolders = files.compactMap { file -> DriveFolder? in
                            guard let id = file["id"] as? String, let name = file["name"] as? String else { return nil }
                            return DriveFolder(id: id, name: name)
                        }
                        completion(.success(mappedFolders))
                    } catch { completion(.failure(error)) }
                }.resume()
            }
        }
    }
}
