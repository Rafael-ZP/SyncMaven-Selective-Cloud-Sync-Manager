//
// AccountManager.swift
// SyncMaven
//

import Foundation
import Combine
import AppKit

public struct SyncMavenAccount: Codable, Identifiable, Equatable {
    public let id: String
    public var email: String
    public var name: String?
    public var avatarData: Data?
}

final class AccountManager: ObservableObject {
    static let shared = AccountManager()
    private init() {
        load()
        // call async import at startup (non-blocking)
        DispatchQueue.global(qos: .utility).async {
            self.importLegacyTokensNow()
        }
    }

    @Published private(set) var accounts: [SyncMavenAccount] = []

    private let metaKey = "SyncMaven.Accounts"
    private let legacyTokenKey = "SyncMaven.GoogleDrive.Tokens" // older oauth path
    private let keychainService = "SyncMaven" // used if tokens saved to Keychain

    // MARK: — Public API

    /// Add account using tokens returned from OAuth flow (access required).
    /// This will fetch userinfo, persist metadata and store tokens in Keychain (best-effort).
    func addAccount(usingAccessToken accessToken: String, refreshToken: String?) {
        fetchUserInfo(accessToken: accessToken) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch res {
                case .failure(let err):
                    AppState.shared.log("Account add failed: \(err.localizedDescription)")
                case .success(let user):
                    let id = UUID().uuidString
                    var acct = SyncMavenAccount(id: id, email: user.email, name: user.name, avatarData: nil)

                    // Save tokens to Keychain for future safe storage (best-effort)
                    let tokenDict: [String: String?] = ["accessToken": accessToken, "refreshToken": refreshToken]
                    if let d = try? JSONEncoder().encode(tokenDict) {
                        KeychainHelper.shared.save(data: d, service: self.keychainService, account: "Account.\(id)")
                    }

                    if let pic = user.picture, let url = URL(string: pic) {
                        URLSession.shared.dataTask(with: url) { data, _, _ in
                            DispatchQueue.main.async {
                                acct.avatarData = data
                                self.appendAndPersist(acct)
                                AppState.shared.log("Account added: \(acct.email)")
                            }
                        }.resume()
                    } else {
                        self.appendAndPersist(acct)
                        AppState.shared.log("Account added: \(acct.email)")
                    }
                }
            }
        }
    }
    private let legacyImportFlag = "SyncMaven.LegacyImportCompleted"
    func remove(account: SyncMavenAccount) {
        NSLog("[AccountManager] Removing account \(account.email) id=\(account.id)")

        // delete tokens
        KeychainHelper.shared.delete(service: keychainService, account: "Account.\(account.id)")

        // remove from metadata array
        accounts.removeAll { $0.id == account.id }
        saveMetadata()

        // Update watched folders that pointed to this removed account
        DispatchQueue.global(qos: .utility).async {
            var folders = Persistence.shared.loadWatchedFolders()
            var modified = false
            for i in folders.indices {
                if folders[i].accountID == account.id {
                    let replacement = AccountManager.shared.accounts.first?.id ?? ""
                    NSLog("[AccountManager] Reassigning folder '\(folders[i].localPath)' accountID -> '\(replacement)'")
                    folders[i].accountID = replacement
                    modified = true
                }
            }
            if modified {
                Persistence.shared.saveWatchedFolders(folders)
                DispatchQueue.main.async {
                    // notify AppState to reload
                    AppState.shared.watchedFolders = folders
                }
            }
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

  
    /// This is robust: it detects multiple stored formats (["accessToken":...], OAuth2PKCE.Tokens, legacy keys).
    func tokens(for accountID: String) -> (accessToken: String, refreshToken: String?)? {
        NSLog("[AccountManager] tokens(for:) lookup for id=\(accountID)")
        guard let d = KeychainHelper.shared.load(service: keychainService, account: "Account.\(accountID)") else {
            NSLog("[AccountManager] Keychain.load returned NIL for Account.\(accountID)")
            return nil
        }

        // Try multiple decoding strategies & log
        if let dict = try? JSONDecoder().decode([String: String?].self, from: d) {
            NSLog("[AccountManager] Decoded keychain dict: \(dict)")
            if let access = dict["accessToken"] ?? dict["access_token"], let a = access {
                let refresh = dict["refreshToken"] ?? dict["refresh_token"]
                return (a, refresh ?? nil)
            }
        }

        // fallback try decode to OAuth2PKCE.Tokens (older shape)
        if let tok = try? JSONDecoder().decode(OAuth2PKCE.Tokens.self, from: d) {
            NSLog("[AccountManager] Decoded OAuth2PKCE.Tokens from keychain")
            return (tok.accessToken, tok.refreshToken)
        }

        NSLog("[AccountManager] Unable to decode tokens for Account.\(accountID)")
        return nil
    }
    
    func importLegacyTokensNow() {
        // Prevent running again if already migrated once
        if UserDefaults.standard.bool(forKey: legacyImportFlag) {
            NSLog("[AccountManager] Legacy import already completed — skipping.")
            return
        }

        NSLog("[AccountManager] importLegacyTokensNow() starting. existing accounts count = \(accounts.count)")

        let legacyAccess = UserDefaults.standard.string(forKey: "SyncMaven.AccessToken")
        let legacyRefresh = UserDefaults.standard.string(forKey: "SyncMaven.RefreshToken")

        guard let access = legacyAccess, let refresh = legacyRefresh else {
            NSLog("[AccountManager] No legacy tokens found — nothing to import.")
            UserDefaults.standard.set(true, forKey: legacyImportFlag)
            return
        }

        let tok = OAuth2PKCE.Tokens(accessToken: access, refreshToken: refresh, expiresAt: nil, tokenType: nil)

        self.fetchUserInfo(accessToken: access) { result in
            switch result {
            case .failure(let err):
                NSLog("[AccountManager] fetchUserInfo failed: \(err)")
                // Still mark import done to prevent infinite retry
                UserDefaults.standard.set(true, forKey: self.legacyImportFlag)
            case .success(let info):
                let id = UUID().uuidString
                var acc = SyncMavenAccount(
                    id: id,
                    email: info.email,
                    name: info.name,
                    avatarData: nil
                )

                // save tokens in Keychain
                if let data = try? JSONEncoder().encode(tok) {
                    KeychainHelper.shared.save(data: data, service: "SyncMaven", account: "Account.\(id)")
                    NSLog("[AccountManager] Migrated tokens to Keychain for Account.\(id)")
                }

                // fetch avatar async
                if let urlString = info.picture, let url = URL(string: urlString) {
                    URLSession.shared.dataTask(with: url) { data, _, _ in
                        acc.avatarData = data
                        DispatchQueue.main.async {
                            self.accounts.append(acc)
                            self.saveMetadata()
                        }
                    }.resume()
                } else {
                    self.accounts.append(acc)
                    self.saveMetadata()
                }

                // REMOVE legacy tokens so it CAN’T re-import again
                UserDefaults.standard.removeObject(forKey: "SyncMaven.AccessToken")
                UserDefaults.standard.removeObject(forKey: "SyncMaven.RefreshToken")

                // Mark import done forever
                UserDefaults.standard.set(true, forKey: self.legacyImportFlag)

                NSLog("[AccountManager] Imported legacy account: \(info.email)")
            }
        }
    }

        // ensure appendAndPersist is main-thread safe
        private func appendAndPersist(_ acct: SyncMavenAccount) {
            DispatchQueue.main.async {
                self.accounts.removeAll { $0.email.lowercased() == acct.email.lowercased() }
                self.accounts.append(acct)
                self.saveMetadata()
            }
        }

    private func persistAllMetadata() {
        if let d = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(d, forKey: metaKey)
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: "SyncMaven.Accounts") {
            do {
                let decoded = try JSONDecoder().decode([SyncMavenAccount].self, from: data)
                accounts = decoded
                NSLog("[AccountManager] Loaded \(accounts.count) accounts from metadata")
            } catch {
                NSLog("[AccountManager] Failed to decode accounts: \(error)")
            }
        } else {
            accounts = []
            NSLog("[AccountManager] No stored accounts found.")
        }

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    // Saves only the lightweight metadata (id, email, avatar) — NOT tokens.
    private func saveMetadata() {
        do {
            let data = try JSONEncoder().encode(accounts)
            UserDefaults.standard.set(data, forKey: "SyncMaven.Accounts")
            NSLog("[AccountManager] saveMetadata() wrote \(accounts.count) accounts")
        } catch {
            NSLog("[AccountManager] saveMetadata() failed: \(error)")
        }
    }

    // MARK: — Legacy token import (UserDefaults)
    // If the app has tokens stored by the older OAuth2PKCE (single-account in UserDefaults),
    // import a metadata account for it so the UI shows the account.
    private func importLegacyTokensIfNeeded() {
        // if we already have accounts, do nothing
        if !accounts.isEmpty { return }

        // read legacy token JSON from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: legacyTokenKey) else { return }
        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // accept both "access_token" and "accessToken"
        let access = (parsed["access_token"] as? String) ?? (parsed["accessToken"] as? String)
        let refresh = (parsed["refresh_token"] as? String) ?? (parsed["refreshToken"] as? String)

        guard let accessToken = access else { return }

        // fetch userinfo and create account metadata
        fetchUserInfo(accessToken: accessToken) { [weak self] res in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch res {
                case .failure(let err):
                    AppState.shared.log("Import legacy tokens failed: \(err.localizedDescription)")
                case .success(let user):
                    let id = UUID().uuidString
                    var acct = SyncMavenAccount(id: id, email: user.email, name: user.name, avatarData: nil)
                    // store tokens to keychain (migrate)
                    let tokenDict: [String: String?] = ["accessToken": accessToken, "refreshToken": refresh]
                    if let d = try? JSONEncoder().encode(tokenDict) {
                        KeychainHelper.shared.save(data: d, service: self.keychainService, account: "Account.\(id)")
                    }
                    if let pic = user.picture, let url = URL(string: pic), let data = try? Data(contentsOf: url) {
                        acct.avatarData = data
                    }
                    self.appendAndPersist(acct)
                    AppState.shared.log("Imported legacy account: \(acct.email)")
                }
            }
        }
    }

    // MARK: — Google userinfo
    private struct GoogleUserInfo: Decodable {
        let email: String
        let name: String?
        let picture: String?
    }

    private func fetchUserInfo(accessToken: String, completion: @escaping (Result<GoogleUserInfo, Error>) -> Void) {
        let url = URL(string: "https://www.googleapis.com/oauth2/v3/userinfo")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { return completion(.failure(err)) }
            guard let data = data else {
                return completion(.failure(NSError(domain: "SyncMaven", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
            }

            do {
                let user = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
                completion(.success(user))
            } catch {
                print("userinfo failed raw:", String(data: data, encoding: .utf8) ?? "nil")
                completion(.failure(error))
            }
        }.resume()
    }
    /// DEBUG: Print raw keychain data for a given accountID
    func debugPrintKeychain(for accountID: String) {
        print("\n---------- DEBUG Keychain (\(accountID)) ----------")

        guard let d = KeychainHelper.shared.load(service: keychainService,
                                                 account: "Account.\(accountID)") else {
            print("Keychain entry NOT FOUND.")
            print("-------------------------------------------\n")
            return
        }

        print("Raw Data (bytes): \(d.count) bytes")

        if let rawString = String(data: d, encoding: .utf8) {
            print("Raw as UTF-8 string:\n\(rawString)")
        } else {
            print("Raw cannot decode as UTF-8")
        }

        // Try JSON decode as ANY dictionary
        if let json = try? JSONSerialization.jsonObject(with: d) {
            print("JSONSerialization result:\n\(json)")
        } else {
            print("JSONSerialization: FAILED")
        }

        // Try decode as [String:String?]
        if let dict = try? JSONDecoder().decode([String:String?].self, from: d) {
            print("Decoded as [String:String?]:\n\(dict)")
        } else {
            print("Decode as [String:String?] FAILED")
        }

        // Try decode as OAuth2PKCE.Tokens
        if let tok = try? JSONDecoder().decode(OAuth2PKCE.Tokens.self, from: d) {
            print("Decoded as OAuth2PKCE.Tokens:")
            print("  accessToken=\(tok.accessToken)")
            print("  refreshToken=\(tok.refreshToken ?? "<nil>")")
            print("  expiresAt=\(String(describing: tok.expiresAt))")
        } else {
            print("Decode as OAuth2PKCE.Tokens FAILED")
        }

        print("-------------------------------------------\n")
    }
}
