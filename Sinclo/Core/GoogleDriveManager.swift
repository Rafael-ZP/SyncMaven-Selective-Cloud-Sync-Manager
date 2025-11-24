//
//  GoogleDriveManager.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


import Foundation
import AppKit

final class GoogleDriveManager {
    static let shared = GoogleDriveManager()
    private init() {}

    private let baseURL = "https://www.googleapis.com/drive/v3"
    private let uploadURL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"

    // MARK: - Auth helpers
    private func withValidAccessToken(completion: @escaping (Result<String, Error>) -> Void) {
        if let tokens = OAuth2PKCE.shared.loadTokens() {
            if let exp = tokens.expiresAt, exp > Date().addingTimeInterval(10) {
                completion(.success(tokens.accessToken))
                return
            } else if tokens.refreshToken != nil {
                // refresh then return
                OAuth2PKCE.shared.refreshTokensIfNeeded { res in
                    switch res {
                    case .success(let t): completion(.success(t.accessToken))
                    case .failure(let e): completion(.failure(e))
                    }
                }
                return
            } else {
                completion(.failure(NSError(domain: "GDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "No valid token"])))
                return
            }
        } else {
            completion(.failure(NSError(domain: "GDrive", code: 2, userInfo: [NSLocalizedDescriptionKey: "No tokens stored"])))
        }
    }

    // MARK: - List folders (root children of Drive)
    func listFolders(completion: @escaping (Result<[(id: String, name: String)], Error>) -> Void) {
        withValidAccessToken { res in
            switch res {
            case .failure(let e): completion(.failure(e))
            case .success(let token):
                var comps = URLComponents(string: "\(self.baseURL)/files")!
                // q= mimeType='application/vnd.google-apps.folder' and trashed=false
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

    // MARK: - Create folder (at root)
    func createFolder(named name: String, completion: @escaping (Result<String, Error>) -> Void) {
        withValidAccessToken { res in
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

    // MARK: - Upload (multipart)
    func upload(fileURL: URL, parentFolderID: String?, completion: @escaping (Result<Void, Error>) -> Void) {
        withValidAccessToken { res in
            switch res {
            case .failure(let e): completion(.failure(e))
            case .success(let token):
                do {
                    let fileData = try Data(contentsOf: fileURL)
                    let metadata: [String:Any] = {
                        // explicitly typed as [String: Any] so we can assign arrays to keys
                        var m: [String: Any] = [
                            "name": fileURL.lastPathComponent,
                            "mimeType": "application/octet-stream"
                        ]
                        if let parent = parentFolderID {
                            m["parents"] = [ parent ]   // now allowed because m is [String:Any]
                        }
                        return m
                    }()
                    let metaJSON = try JSONSerialization.data(withJSONObject: metadata)
                    let boundary = "===============\(UUID().uuidString)"
                    var body = Data()
                    // metadata
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
                    body.append(metaJSON)
                    body.append("\r\n".data(using: .utf8)!)
                    // file
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
                    body.append(fileData)
                    body.append("\r\n".data(using: .utf8)!)
                    // end
                    body.append("--\(boundary)--".data(using: .utf8)!)

                    var req = URLRequest(url: URL(string: self.uploadURL)!)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    req.httpBody = body
                    req.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

                    URLSession.shared.dataTask(with: req) { data, resp, err in
                        if let err = err { completion(.failure(err)); return }
                        // Optionally parse result to confirm success
                        completion(.success(()))
                    }.resume()
                } catch { completion(.failure(error)) }
            }
        }
    }
}
