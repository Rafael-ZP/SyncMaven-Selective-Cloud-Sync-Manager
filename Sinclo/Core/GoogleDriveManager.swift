import Foundation
import AppKit

final class GoogleDriveManager: NSObject {
    static let shared = GoogleDriveManager()
    
    private let baseURL = "https://www.googleapis.com/drive/v3"
    private let uploadURL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"
    
    private var urlSession: URLSession!
    private var uploadTasks: [Int: ResumableUploadTask] = [:]

    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
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

    func upload(fileURL: URL, accountID: String, parentFolderID: String?, progress: @escaping (Double) -> Void, completion: @escaping (Result<String, Error>) -> Void) {
        let task = ResumableUploadTask(fileURL: fileURL, accountID: accountID, parentFolderID: parentFolderID, progress: progress, completion: completion)
        initiateResumableSession(for: task)
    }

    private func initiateResumableSession(for task: ResumableUploadTask) {
        withValidAccessToken(accountID: task.accountID) { result in
            switch result {
            case .failure(let error):
                task.completion(.failure(error))
            case .success(let token):
                do {
                    let fileData = try Data(contentsOf: task.fileURL)
                    let metadata: [String: Any] = [
                        "name": task.fileURL.lastPathComponent,
                        "parents": task.parentFolderID != nil ? [task.parentFolderID!] : []
                    ]
                    
                    var request = URLRequest(url: URL(string: self.uploadURL)!)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: metadata)

                    let dataTask = self.urlSession.dataTask(with: request) { [weak self] _, response, error in
                        if let error = error {
                            task.completion(.failure(error))
                            return
                        }
                        guard let httpResponse = response as? HTTPURLResponse,
                              (200...299).contains(httpResponse.statusCode),
                              let location = httpResponse.allHeaderFields["Location"] as? String,
                              let sessionURI = URL(string: location) else {
                            task.completion(.failure(NSError(domain: "GDrive", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to initiate resumable session."])))
                            return
                        }
                        task.uploadSessionURI = sessionURI
                        self?.uploadFile(for: task)
                    }
                    dataTask.resume()
                } catch {
                    task.completion(.failure(error))
                }
            }
        }
    }

    private func uploadFile(for task: ResumableUploadTask) {
        guard let sessionURI = task.uploadSessionURI else {
            task.completion(.failure(NSError(domain: "GDrive", code: 11, userInfo: [NSLocalizedDescriptionKey: "Missing upload session URI."])))
            return
        }
        
        var request = URLRequest(url: sessionURI)
        request.httpMethod = "PUT"
        request.timeoutInterval = 3600 // 1 hour
        
        let uploadTask = self.urlSession.uploadTask(with: request, fromFile: task.fileURL)
        self.uploadTasks[uploadTask.taskIdentifier] = task
        uploadTask.resume()
    }

    func listFolders(accountID: String, completion: @escaping (Result<[(id: String, name: String)], Error>) -> Void) {
        withValidAccessToken(accountID: accountID) { res in
            print("🔍 DEBUG: withValidAccessToken called with accountID = \(accountID)")
            print("🔍 Existing Account IDs:", AccountManager.shared.accounts.map { $0.id })
            switch res {
                
            case .failure(let e): completion(.failure(e))
            case .success(let token):
                var comps = URLComponents(string: "\(self.baseURL)/files")!
                comps.queryItems = [
                    URLQueryItem(name: "q", value: "mimeType='application/vnd.google-apps.folder' and trashed=false"),
                    URLQueryItem(name: "fields", value: "files(id,name)")
                ]
                var req = URLRequest(url: comps.url!)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let err = err { completion(.failure(err)); return }
                    guard let d = data else { completion(.failure(NSError(domain: "GDrive", code: 3, userInfo: nil))); return }
                    do {
                        let json = try JSONSerialization.jsonObject(with: d) as? [String:Any]
                        let files = (json?["files"] as? [[String:Any]]) ?? []
                        let mapped = files.compactMap { f -> (String, String)? in
                            if let id = f["id"] as? String, let name = f["name"] as? String { return (id, name) }
                            return nil
                        }
                        completion(.success(mapped))
                    } catch { completion(.failure(error)) }
                }.resume()
            }
        }
    }

    func createFolder(accountID: String, name: String, completion: @escaping (Result<String, Error>) -> Void) {
        withValidAccessToken(accountID: accountID) { res in
            switch res {
            case .failure(let e): completion(.failure(e))
            case .success(let token):
                let url = URL(string: "\(self.baseURL)/files")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                let body: [String:Any] = ["name": name, "mimeType": "application/vnd.google-apps.folder"]
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                URLSession.shared.dataTask(with: req) { data, resp, err in
                    if let err = err { completion(.failure(err)); return }
                    guard let d = data else { completion(.failure(NSError(domain: "GDrive", code: 4, userInfo: nil))); return }
                    do {
                        let json = try JSONSerialization.jsonObject(with: d) as? [String:Any]
                        if let id = json?["id"] as? String { completion(.success(id)); return }
                        completion(.failure(NSError(domain: "GDrive", code: 5, userInfo: nil)))
                    } catch { completion(.failure(error)) }
                }.resume()
            }
        }
    }

    func delete(fileID: String, accountID: String, completion: @escaping (Error?) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let token):
                let url = URL(string: "\(self.baseURL)/files/\(fileID)")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                URLSession.shared.dataTask(with: request) { _, response, error in
                    if let error = error {
                        completion(error)
                        return
                    }
                    if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                        completion(NSError(domain: "GDrive", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Delete failed"]))
                    } else {
                        completion(nil)
                    }
                }.resume()
            }
        }
    }

    func listChildren(folderID: String, accountID: String, completion: @escaping (Result<[String: String], Error>) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let token):
                var comps = URLComponents(string: "\(self.baseURL)/files")!
                comps.queryItems = [
                    URLQueryItem(name: "q", value: "'\(folderID)' in parents and trashed=false"),
                    URLQueryItem(name: "fields", value: "files(id,name)")
                ]
                var req = URLRequest(url: comps.url!)
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                URLSession.shared.dataTask(with: req) { data, _, error in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    guard let data = data else {
                        completion(.failure(NSError(domain: "GDrive", code: 13, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                        return
                    }
                    do {
                        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                        let files = (json?["files"] as? [[String: Any]]) ?? []
                        let fileMap = files.reduce(into: [String: String]()) { result, file in
                            if let id = file["id"] as? String, let name = file["name"] as? String {
                                result[name] = id
                            }
                        }
                        completion(.success(fileMap))
                    } catch {
                        completion(.failure(error))
                    }
                }.resume()
            }
        }
    }

    func download(fileID: String, to localUrl: URL, accountID: String, completion: @escaping (Error?) -> Void) {
        withValidAccessToken(accountID: accountID) { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let token):
                let url = URL(string: "\(self.baseURL)/files/\(fileID)?alt=media")!
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                
                let downloadTask = self.urlSession.downloadTask(with: request) { url, response, error in
                    if let error = error {
                        completion(error)
                        return
                    }
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        completion(NSError(domain: "GDrive", code: 15, userInfo: [NSLocalizedDescriptionKey: "Download failed"]))
                        return
                    }
                    guard let tempUrl = url else {
                        completion(NSError(domain: "GDrive", code: 16, userInfo: [NSLocalizedDescriptionKey: "No temporary URL for downloaded file"]))
                        return
                    }
                    do {
                        try FileManager.default.moveItem(at: tempUrl, to: localUrl)
                        completion(nil)
                    } catch {
                        completion(error)
                    }
                }
                downloadTask.resume()
            }
        }
    }


    private func withValidAccessToken(accountID: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let (accessToken, _) = AccountManager.shared.tokens(for: accountID) else {
            completion(.failure(NSError(domain: "GDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid token for account"])))
            return
        }
        completion(.success(accessToken))
    }
}

extension GoogleDriveManager: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if let uploadTask = self.uploadTasks[dataTask.taskIdentifier] {
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let fileID = json?["id"] as? String {
                    uploadTask.completion(.success(fileID))
                } else {
                    uploadTask.completion(.failure(NSError(domain: "GDrive", code: 14, userInfo: [NSLocalizedDescriptionKey: "Could not find file ID in response."])))
                }
            } catch {
                uploadTask.completion(.failure(error))
            }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if let uploadTask = self.uploadTasks[task.taskIdentifier] {
            let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            uploadTask.progress(progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let uploadTask = self.uploadTasks[task.taskIdentifier] else { return }
        
        if let error = error {
            uploadTask.completion(.failure(error))
        } else {
            if let response = task.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                uploadTask.completion(.failure(NSError(domain: "GDrive", code: 12, userInfo: [NSLocalizedDescriptionKey: "Upload failed with status: \(response.statusCode)"])))
            }
        }
        self.uploadTasks.removeValue(forKey: task.taskIdentifier)
    }
}
