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

    // ------------------------------------------------------
    // SET YOUR GOOGLE DESKTOP CLIENT ID HERE
    // ------------------------------------------------------
    private let clientID = "426014651712-4qiheogmncb4id0cjmoevidngqdtjpk6.apps.googleusercontent.com"
    private let clientSecret = "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"
    private let scope = "https://www.googleapis.com/auth/drive"

    private var codeVerifier: String?
    private var state: String?
    private var listener: NWListener?
    private var redirectPort: UInt16 = 0

    struct Tokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let tokenType: String?
    }
    func refreshTokensIfNeeded(completion: @escaping (Result<OAuth2PKCE.Tokens, Error>) -> Void) {
        guard let tokens = loadTokens(),
              let refresh = tokens.refreshToken else {
            completion(.failure(NSError(domain: "OAuth", code: 50, userInfo: [
                NSLocalizedDescriptionKey: "No refresh token available"
            ])))
            return
        }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.httpBody = [
            "client_id": clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ].percentEncoded()

        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else {
                completion(.failure(NSError(domain: "OAuth", code: 51)))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let newAccess = json?["access_token"] as? String else {
                    completion(.failure(NSError(domain: "OAuth", code: 52)))
                    return
                }

                let expiresIn = json?["expires_in"] as? Int

                let updated = Tokens(
                    accessToken: newAccess,
                    refreshToken: refresh,
                    expiresAt: expiresIn != nil ? Date().addingTimeInterval(TimeInterval(expiresIn!)) : nil,
                    tokenType: json?["token_type"] as? String
                )

                self.saveTokens(updated)
                completion(.success(updated))

            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    private let tokenKey = "Sinclo.GoogleDrive.Tokens"

    // MARK: - Start auth
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
                    completion(.failure(error))
                    return
                }

                guard let code = code, returnedState == self.state else {
                    completion(.failure(NSError(domain: "OAuth", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Invalid OAuth response"
                    ])))
                    return
                }

                let redirectURI = "http://127.0.0.1:\(self.redirectPort)"
                self.exchangeCodeForTokens(code: code,
                                           codeVerifier: verifier,
                                           redirectURI: redirectURI,
                                           completion: completion)
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

    // MARK: - Token exchange
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
        body["client_secret"] = clientSecret ?? ""

        req.httpBody = body.percentEncoded()
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else {
                return completion(.failure(NSError(domain: "OAuth", code: 5)))
            }

            do {
                print("[OAuth] Token response raw: \(String(data: data, encoding: .utf8) ?? "<nil>")")
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let access = json?["access_token"] as? String else {
                    return completion(.failure(NSError(domain: "OAuth", code: 8, userInfo: [
                        NSLocalizedDescriptionKey: "No access_token in response"
                    ])))
                }

                let refresh = json?["refresh_token"] as? String
                let expiresIn = json?["expires_in"] as? Int
                let type = json?["token_type"] as? String

                let expiresAt = expiresIn != nil ? Date().addingTimeInterval(TimeInterval(expiresIn!)) : nil

                let tokens = Tokens(accessToken: access,
                                    refreshToken: refresh,
                                    expiresAt: expiresAt,
                                    tokenType: type)

                self.saveTokens(tokens)
                completion(.success(tokens))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: Loopback server
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

        // Add this property at top of startLoopbackListener (just before listener?.newConnectionHandler)
        var handled = AtomicBool(false) // thread-safe single-run guard

        listener?.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                guard let data = data,
                      let reqStr = String(data: data, encoding: .utf8)
                else {
                    print("[OAuth] Received invalid data on loopback")
                    // don't treat as fatal OAuth error; ignore
                    return
                }

                // DEBUG: print the full request so we can inspect exactly what arrived
                print("[OAuth] Incoming HTTP request:\n\(reqStr)")

                // Parse first line
                let firstLine = reqStr.components(separatedBy: "\r\n").first ?? ""
                print("[OAuth] First line: \(firstLine)")
                let parts = firstLine.split(separator: " ")
                guard parts.count >= 2 else {
                    print("[OAuth] Malformed request first line")
                    return
                }

                let path = String(parts[1])  // "/?code=..&state=.." or "/favicon.ico"
                print("[OAuth] Parsed path: \(path)")

                // Build URLComponents and try extract code/state
                guard let url = URL(string: "http://localhost\(path)"),
                      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    print("[OAuth] Failed to build URL from path")
                    return
                }

                let code = comps.queryItems?.first(where: { $0.name == "code" })?.value
                let state = comps.queryItems?.first(where: { $0.name == "state" })?.value
                print("[OAuth] Extracted code: \(String(describing: code)), state: \(String(describing: state))")

                // If there is no code, this is not the auth callback (e.g., /favicon.ico). Ignore.
                guard let foundCode = code else {
                    print("[OAuth] No code in request — ignoring (likely favicon or other asset).")
                    // still respond to browser to avoid hanging connections (send small 204)
                    let emptyResp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n"
                    conn.send(content: emptyResp.data(using: .utf8), completion: .contentProcessed({ _ in
                        conn.cancel()
                    }))
                    return
                }

                // Ensure we only handle the first valid callback once
                if handled.testAndSet() {
                    print("[OAuth] Already handled auth callback; ignoring subsequent valid callback.")
                    // reply but return
                    let html = "<html><body><h3>Sinclo: Login already handled. You can close this tab.</h3></body></html>"
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.count)\r\n\r\n\(html)"
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in
                        conn.cancel()
                    }))
                    return
                }

                // Prepare success response for the browser
                let html = "<html><body><h3>Sinclo: Login Complete. You can close this tab.</h3></body></html>"
                let resp =
                """
                HTTP/1.1 200 OK\r
                Content-Type: text/html\r
                Content-Length: \(html.count)\r
                \r
                \(html)
                """

                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed({ _ in
                    conn.cancel()
                }))

                // Call the callback with the found code/state
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

    // MARK: Token storage
    func saveTokens(_ t: Tokens) {
        if let d = try? JSONEncoder().encode(t) {
            UserDefaults.standard.set(d, forKey: tokenKey)
        }
    }

    func loadTokens() -> Tokens? {
        guard let d = UserDefaults.standard.data(forKey: tokenKey) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: d)
    }

    func clearTokens() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
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

