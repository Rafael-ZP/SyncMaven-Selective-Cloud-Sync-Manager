import Foundation
import Network
import CryptoKit
import AppKit

final class AtomicBool {
    private let queue = DispatchQueue(label: "atomic.bool.queue")
    private var _value: Bool
    init(_ value: Bool = false) { _value = value }
    func testAndSet() -> Bool {
        return queue.sync {
            if _value { return true }
            _value = true
            return false
        }
    }
}

final class OAuth2PKCE {
    static let shared = OAuth2PKCE()
    private init() {}

    public struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let tokenType: String?
    }

    // ------------------------------------------------------
    // SET YOUR GOOGLE DESKTOP CLIENT ID / SECRET (if any) HERE
    // ------------------------------------------------------
    private let clientID = "426014651712-bs8fqlmf9i0fcn3vro0ucl8svolss0up.apps.googleusercontent.com"
    private let clientSecret: String? = "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" // nil if public client

    // default scope used during interactive auth (open id + email + profile + drive)
    private let scope = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/drive",
        "https://www.googleapis.com/auth/drive.metadata.readonly",
        "https://www.googleapis.com/auth/drive.readonly"
    ].joined(separator: " ")

    private var codeVerifier: String?
    private var state: String?
    private var listener: NWListener?
    private var redirectPort: UInt16 = 0

    // legacy key (single-account storage used by older versions)
    private let legacyTokenKey = "Sinclo.GoogleDrive.Tokens"

    // per-account token key prefix in UserDefaults (keeps legacy for compatibility)
    private func tokenKey(for accountID: String) -> String {
        return "Sinclo.GoogleDrive.Tokens.\(accountID)"
    }

    // -----------------------------
    // Public: try refreshing tokens for an account (or legacy)
    // -----------------------------
    func refreshTokensIfNeeded(for accountID: String? = nil, completion: @escaping (Result<Tokens, Error>) -> Void) {
        // Attempt to load stored tokens for this account (or legacy)
        guard let stored = loadTokens(for: accountID) else {
            completion(.failure(NSError(domain: "OAuth", code: 100, userInfo: [NSLocalizedDescriptionKey: "No stored tokens to refresh"])))
            return
        }

        // If access token still valid, return it
        if let exp = stored.expiresAt, exp > Date().addingTimeInterval(10) {
            completion(.success(stored))
            return
        }

        // Need refresh token
        guard let refresh = stored.refreshToken, !refresh.isEmpty else {
            completion(.failure(NSError(domain: "OAuth", code: 101, userInfo: [NSLocalizedDescriptionKey: "No refresh token available"])))
            return
        }

        // Build request to token endpoint
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"

        var body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ]
        if let secret = clientSecret {
            body["client_secret"] = secret
        }

        req.httpBody = body.percentEncoded()
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err {
                completion(.failure(err)); return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "OAuth", code: 102, userInfo: [NSLocalizedDescriptionKey: "No data from token refresh"])))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let errObj = json?["error"] {
                    let msg = (json?["error_description"] as? String) ?? "\(errObj)"
                    completion(.failure(NSError(domain: "OAuth", code: 103, userInfo: [NSLocalizedDescriptionKey: msg])))
                    return
                }

                guard let access = json?["access_token"] as? String else {
                    completion(.failure(NSError(domain: "OAuth", code: 104, userInfo: [NSLocalizedDescriptionKey: "No access_token in refresh response"])))
                    return
                }

                let expiresIn = json?["expires_in"] as? Int
                let tokenType = json?["token_type"] as? String
                // refresh_token sometimes returned only on initial exchange; prefer existing
                let newRefresh = (json?["refresh_token"] as? String) ?? stored.refreshToken

                let newTokens = Tokens(
                    accessToken: access,
                    refreshToken: newRefresh,
                    expiresAt: expiresIn != nil ? Date().addingTimeInterval(TimeInterval(expiresIn!)) : nil,
                    tokenType: tokenType
                )

                // persist updated tokens (for account or legacy)
                self.saveTokens(newTokens, for: accountID)

                completion(.success(newTokens))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // -----------------------------
    // Public: start interactive auth (returns Tokens tuple on success).
    // Use completion to get tokens and then persist them using AccountManager or saveTokens(for:)
    // -----------------------------
    func startAuthorization(completion: @escaping (Result<Tokens, Error>) -> Void) {
        do {
            // PKCE setup
            let verifier = randomString(length: 64)
            codeVerifier = verifier
            let challenge = codeChallenge(from: verifier)
            state = randomString(length: 16)

            // Start listener on any port
            let port = try startLoopbackListener { [weak self] code, returnedState, error in
                guard let self = self else { return }
                self.stopLoopbackListener()

                if let error = error {
                    completion(.failure(error)); return
                }
                guard let code = code, returnedState == self.state else {
                    completion(.failure(NSError(domain: "OAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth response"])))
                    return
                }

                let redirectURI = "http://127.0.0.1:\(self.redirectPort)"
                self.exchangeCodeForTokens(code: code, codeVerifier: verifier, redirectURI: redirectURI, completion: completion)
            }

            // Build authorization URL
            let redirectURI = "http://127.0.0.1:\(port)"
            var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            comps.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scope),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: state)
            ]
            if let url = comps.url {
                print("[OAuth] Opening auth URL: \(url.absoluteString)")
                NSWorkspace.shared.open(url)
            }
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: - Token exchange (code -> tokens)
    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        redirectURI: String,
        completion: @escaping (Result<Tokens, Error>) -> Void
    ) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"

        var body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier
        ]
        if let secret = clientSecret {
            body["client_secret"] = secret
        }

        req.httpBody = body.percentEncoded()
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else {
                completion(.failure(NSError(domain: "OAuth", code: 5)))
                return
            }

            do {
                print("[OAuth] Token response raw: \(String(data: data, encoding: .utf8) ?? "<nil>")")
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let errObj = json?["error"] {
                    let msg = (json?["error_description"] as? String) ?? "\(errObj)"
                    completion(.failure(NSError(domain: "OAuth", code: 6, userInfo: [NSLocalizedDescriptionKey: msg])))
                    return
                }

                guard let access = json?["access_token"] as? String else {
                    return completion(.failure(NSError(domain: "OAuth", code: 8, userInfo: [NSLocalizedDescriptionKey: "No access_token in response"])))
                }

                let refresh = json?["refresh_token"] as? String
                let expiresIn = json?["expires_in"] as? Int
                let type = json?["token_type"] as? String

                let expiresAt = expiresIn != nil ? Date().addingTimeInterval(TimeInterval(expiresIn!)) : nil

                let tokens = Tokens(accessToken: access,
                                    refreshToken: refresh,
                                    expiresAt: expiresAt,
                                    tokenType: type)

                // Do NOT auto-save to account-specific key here automatically — leave it to caller,
                // but also persist to legacy single-account key for backward compatibility.
                self.saveTokens(tokens, for: nil) // store to legacy spot so older code still works
                completion(.success(tokens))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: Loopback server (unchanged)
    private func startLoopbackListener(
        callback: @escaping (_ code: String?, _ state: String?, _ error: Error?) -> Void
    ) throws -> UInt16 {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: .any)
        let wait = DispatchSemaphore(value: 0)

        var chosenPort: UInt16 = 0

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                chosenPort = self.listener?.port?.rawValue ?? 0
                self.redirectPort = chosenPort
                wait.signal()
            case .failed(let err):
                print("Listener failed: \(err)")
                wait.signal()
            default:
                break
            }
        }

        var handled = AtomicBool(false)

        listener?.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                guard let data = data,
                      let reqStr = String(data: data, encoding: .utf8) else {
                    print("[OAuth] Received invalid data on loopback"); return
                }
                print("[OAuth] Incoming HTTP request:\n\(reqStr)")
                let firstLine = reqStr.components(separatedBy: "\r\n").first ?? ""
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2 else { return }
                let path = String(parts[1])
                guard let url = URL(string: "http://localhost\(path)"),
                      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    print("[OAuth] Failed to build URL from path"); return
                }

                let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
                let state = comps.queryItems?.first(where: { $0.name == "state" })?.value

                guard let foundCode = code else {
                    // respond small 204 to avoid hanging
                    let emptyResp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n"
                    conn.send(content: emptyResp.data(using: .utf8), completion: .contentProcessed({ _ in conn.cancel() }))
                    return
                }

                if handled.testAndSet() {
                    let html = "<html><body><h3>Sinclo: Login already handled. You can close this tab.</h3></body></html>"
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.count)\r\n\r\n\(html)"
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in conn.cancel() }))
                    return
                }

                let html = "<html><body><h3>Sinclo: Login Complete. You can close this tab.</h3></body></html>"
                let resp =
                """
                HTTP/1.1 200 OK\r
                Content-Type: text/html\r
                Content-Length: \(html.count)\r
                \r
                \(html)
                """
                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in conn.cancel() }))
                callback(foundCode, state, nil)
            }
        }

        listener?.start(queue: .global())
        wait.wait()
        return chosenPort
    }

    private func stopLoopbackListener() {
        listener?.cancel()
        listener = nil
    }

    // MARK: Token storage — supports per-account keys & legacy key
    func saveTokens(_ t: Tokens, for accountID: String?) {
        do {
            let d = try JSONEncoder().encode(t)
            if let id = accountID {
                UserDefaults.standard.set(d, forKey: tokenKey(for: id))
            } else {
                // legacy single-account key (keep for backward compatibility)
                UserDefaults.standard.set(d, forKey: legacyTokenKey)
            }
        } catch {
            NSLog("[OAuth] saveTokens encode failed: \(error)")
        }
    }

    func loadTokens(for accountID: String? = nil) -> Tokens? {
        if let id = accountID {
            if let d = UserDefaults.standard.data(forKey: tokenKey(for: id)),
               let t = try? JSONDecoder().decode(Tokens.self, from: d) {
                return t
            }
            return nil
        } else {
            // try legacy key
            if let d = UserDefaults.standard.data(forKey: legacyTokenKey),
               let t = try? JSONDecoder().decode(Tokens.self, from: d) {
                return t
            }
            return nil
        }
    }

    func clearTokens(for accountID: String?) {
        if let id = accountID {
            UserDefaults.standard.removeObject(forKey: tokenKey(for: id))
        } else {
            UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        }
    }

    // MARK: Helpers
    private func randomString(length: Int) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hashed = SHA256.hash(data: data)
        return base64urlEncode(Data(hashed))
    }

    private func base64urlEncode(_ d: Data) -> String {
        return d.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

fileprivate extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        let str = map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!)" }
            .joined(separator: "&")
        return str.data(using: .utf8)
    }
}
