//
//  SincloAccount 2.swift
//  Sinclo
//
//  Created by Rafael Zieganpalg on 26/11/25.
//


// AccountManager.swift
// Keychain-backed token storage & simple account metadata

import Foundation
import Security
import Combine

struct SincloAccount: Codable, Identifiable {
    let id: String
    let email: String
}

final class AccountManager: ObservableObject {
    static let shared = AccountManager()
    @Published private(set) var accounts: [SincloAccount] = []

    private let accountsKey = "Sinclo.Accounts.Metadata" // stores [[String: String]] with id & email

    private init() {
        load()
    }

    // Add account: run OAuth, fetch userinfo, store tokens in Keychain, metadata in UserDefaults
    func addAccount(completion: @escaping (Result<SincloAccount, Error>) -> Void) {
        OAuth2PKCE.shared.startAuthorization { res in
            switch res {
            case .failure(let err):
                completion(.failure(err))
            case .success(let tokens):
                self.fetchUserInfo(accessToken: tokens.accessToken) { r in
                    switch r {
                    case .failure(let e):
                        completion(.failure(e))
                    case .success(let email):
                        let id = UUID().uuidString
                        let acc = SincloAccount(id: id, email: email)
                        // store tokens JSON in Keychain
                        if let d = try? JSONEncoder().encode(tokens) {
                            let _ = KeychainHelper.shared.save(data: d, service: "Sinclo", account: "Account.\(id)")
                        }
                        // store metadata
                        self.saveAccountMetadata(acc)
                        self.load()
                        completion(.success(acc))
                    }
                }
            }
        }
    }

    func remove(account: SincloAccount) {
        // remove keychain entry
        KeychainHelper.shared.delete(service: "Sinclo", account: "Account.\(account.id)")
        // remove metadata
        var meta = loadMetadata()
        meta.removeAll(where: { $0["id"] == account.id })
        UserDefaults.standard.set(meta, forKey: accountsKey)
        load()
    }

    func reload() { load() }

    // helper to retrieve tokens for account id
    func tokens(for accountID: String) -> OAuth2PKCE.Tokens? {
        if let d = KeychainHelper.shared.read(service: "Sinclo", account: "Account.\(accountID)") {
            return try? JSONDecoder().decode(OAuth2PKCE.Tokens.self, from: d)
        }
        return nil
    }

    // MARK: Private helpers
    private func fetchUserInfo(accessToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let e = err { completion(.failure(e)); return }
            guard let d = data else { completion(.failure(NSError(domain: "Account", code: 1))); return }
            if let json = try? JSONSerialization.jsonObject(with: d) as? [String:Any],
               let email = json["email"] as? String {
                completion(.success(email))
            } else {
                completion(.failure(NSError(domain: "Account", code: 2)))
            }
        }.resume()
    }

    private func saveAccountMetadata(_ acc: SincloAccount) {
        var meta = loadMetadata()
        meta.append(["id": acc.id, "email": acc.email])
        UserDefaults.standard.set(meta, forKey: accountsKey)
    }

    private func loadMetadata() -> [[String:String]] {
        return UserDefaults.standard.array(forKey: accountsKey) as? [[String:String]] ?? []
    }

    private func load() {
        let meta = loadMetadata()
        var arr: [SincloAccount] = []
        for m in meta {
            if let id = m["id"], let email = m["email"] {
                arr.append(SincloAccount(id: id, email: email))
            }
        }
        DispatchQueue.main.async { self.accounts = arr }
    }
}