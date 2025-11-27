//
// AccountManager.swift
// Sinclo
//

import Foundation
import Combine
import AppKit

public struct SincloAccount: Codable, Identifiable, Equatable {
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

    @Published private(set) var accounts: [SincloAccount] = []

    private let metaKey = "Sinclo.Accounts"
    private let legacyTokenKey = "Sinclo.GoogleDrive.Tokens" // older oauth path
    private let keychainService = "Sinclo" // used if tokens saved to Keychain

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
                    var acct = SincloAccount(id: id, email: user.email, name: user.name, avatarData: nil)

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
    private let legacyImportFlag = "Sinclo.LegacyImportCompleted"
    func remove(account: SincloAccount) {
        NSLog("[AccountManager] Removing account \(account.email)")

        // remove tokens
        KeychainHelper.shared.delete(service: "Sinclo", account: "Account.\(account.id)")

        // remove from metadata
        accounts.removeAll { $0.id == account.id }
        saveMetadata()

        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

  
    /// This is robust: it detects multiple stored formats (["accessToken":...], OAuth2PKCE.Tokens, legacy keys).
    func tokens(for accountID: String) -> (accessToken: String, refreshToken: String?)? {
        print("\n====== TOKEN LOOKUP DEBUG for \(accountID) ======")

        guard let d = KeychainHelper.shared.load(service: keychainService,
                                                 account: "Account.\(accountID)") else {
            print("Keychain.load returned NIL — no item stored.")
            print("=================================================\n")
            return nil
        }

        print("Loaded raw data: \(d.count) bytes")

        // 1) dictionary type
        if let dict = try? JSONDecoder().decode([String:String?].self, from: d) {
            print("Decoded as [String:String?]: \(dict)")

            if let accessMaybe = dict["accessToken"] ?? dict["access_token"],
               let access = accessMaybe, !access.isEmpty {

                print("→ FOUND accessToken in simple dict")
                let refresh = dict["refreshToken"] ?? dict["refresh_token"] ?? nil
                print("→ FINAL TOKENS: access=\(access.prefix(15))..., refresh=\(refresh ?? "<nil>")")
                print("=================================================\n")
                return (access, refresh)
            } else {
                print("Simple dict decode OK but accessToken missing or empty.")
            }
        } else {
            print("Decode as [String:String?] FAILED")
        }

        // 2) full struct
        if let tok = try? JSONDecoder().decode(OAuth2PKCE.Tokens.self, from: d) {
            print("Decoded as OAuth2PKCE.Tokens → access=\(tok.accessToken.prefix(15))...")

            if !tok.accessToken.isEmpty {
                print("→ FINAL TOKENS (struct): access=\(tok.accessToken.prefix(15))..., refresh=\(tok.refreshToken ?? "<nil>")")
                print("=================================================\n")
                return (tok.accessToken, tok.refreshToken)
            } else {
                print("Token struct decode OK but accessToken empty.")
            }
        } else {
            print("Decode as OAuth2PKCE.Tokens FAILED")
        }

        // 3) legacy JSON
        if let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            print("Decoded via JSONSerialization: \(json)")

            if let access = (json["access_token"] as? String) ?? (json["accessToken"] as? String),
               !access.isEmpty {
                let refresh = (json["refresh_token"] as? String) ?? (json["refreshToken"] as? String)
                print("→ FINAL TOKENS (legacy JSON): access=\(access.prefix(15))..., refresh=\(refresh ?? "<nil>")")
                print("=================================================\n")
                return (access, refresh)
            } else {
                print("Legacy JSON decode OK but access_token not found.")
            }
        } else {
            print("JSONSerialization decode FAILED")
        }

        print("→ FINAL RESULT: NO TOKENS FOUND\n=================================================\n")
        return nil
    }
    
    func importLegacyTokensNow() {
        // Prevent running again if already migrated once
        if UserDefaults.standard.bool(forKey: legacyImportFlag) {
            NSLog("[AccountManager] Legacy import already completed — skipping.")
            return
        }

        NSLog("[AccountManager] importLegacyTokensNow() starting. existing accounts count = \(accounts.count)")

        let legacyAccess = UserDefaults.standard.string(forKey: "Sinclo.AccessToken")
        let legacyRefresh = UserDefaults.standard.string(forKey: "Sinclo.RefreshToken")

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
                var acc = SincloAccount(
                    id: id,
                    email: info.email,
                    name: info.name,
                    avatarData: nil
                )

                // save tokens in Keychain
                if let data = try? JSONEncoder().encode(tok) {
                    KeychainHelper.shared.save(data: data, service: "Sinclo", account: "Account.\(id)")
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
                UserDefaults.standard.removeObject(forKey: "Sinclo.AccessToken")
                UserDefaults.standard.removeObject(forKey: "Sinclo.RefreshToken")

                // Mark import done forever
                UserDefaults.standard.set(true, forKey: self.legacyImportFlag)

                NSLog("[AccountManager] Imported legacy account: \(info.email)")
            }
        }
    }

        // ensure appendAndPersist is main-thread safe
        private func appendAndPersist(_ acct: SincloAccount) {
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
        if let data = UserDefaults.standard.data(forKey: "Sinclo.Accounts") {
            do {
                let decoded = try JSONDecoder().decode([SincloAccount].self, from: data)
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
            UserDefaults.standard.set(data, forKey: "Sinclo.Accounts")
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
                    var acct = SincloAccount(id: id, email: user.email, name: user.name, avatarData: nil)
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
                return completion(.failure(NSError(domain: "Sinclo", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
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
