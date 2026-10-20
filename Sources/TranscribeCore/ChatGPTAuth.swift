import Foundation
import CryptoKit
import Security
import JWTKit

public struct ChatGPTAccount: Codable, Sendable, Identifiable {
    public var id: String { clientID + ":" + subject }
    public var clientID: String
    public var subject: String
    public var email: String?
    public var tokens: ChatGPTTokens?
    public var displayName: String { "\(email ?? "ChatGPT account") · \(clientID.suffix(8))" }
    public var planEnabled: Bool { tokens?.scopes.contains("chatgpt.tokens.use.direct") == true }

    public init(clientID: String, subject: String, email: String?, tokens: ChatGPTTokens?) {
        self.clientID = clientID; self.subject = subject; self.email = email; self.tokens = tokens
    }
}

public struct ChatGPTTokens: Codable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var idToken: String?
    public var expiresAt: Date
    public var scopes: [String]
}

public struct ChatGPTLogin: Sendable {
    public let state: String
    public let nonce: String
    public let verifier: String
    public let redirectURI: String
    public let hostID: String
    public let account: ChatGPTAccount?

    public init(redirectURI: String, hostID: String, account: ChatGPTAccount? = nil) throws {
        self.redirectURI = redirectURI
        self.hostID = hostID
        self.account = account
        state = try Self.random()
        nonce = try Self.random()
        verifier = try Self.random()
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw TranscribeError.message("Cannot prepare a secure ChatGPT sign-in.")
        }
        return Data(bytes).base64URL
    }

    public func authorizationURL() -> URL {
        var parts = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
        var values = ["client_id": account?.clientID ?? "dynamic_agent_client", "ext_agent_host_id": hostID,
                      "response_type": "code", "redirect_uri": redirectURI,
                      "scope": "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct",
                      "resource": "https://api.openai.com/v1", "state": state, "nonce": nonce,
                      "code_challenge_method": "S256", "code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL]
        if let account {
            values["id_token_hint"] = account.tokens?.idToken
            values["login_hint"] = account.email
            if account.tokens != nil && !account.planEnabled { values["prompt"] = "consent" }
        } else { values["agent_name_hint"] = "Transcribe" }
        parts.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }

    public func callback(_ url: URL) throws -> (code: String, clientID: String) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let expected = URLComponents(string: redirectURI), parts.scheme == expected.scheme,
              parts.host == expected.host, parts.port == expected.port, parts.path == expected.path,
              parts.fragment == nil else { throw TranscribeError.message("Unexpected ChatGPT sign-in callback.") }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            guard fields[item.name] == nil, let value = item.value else { throw TranscribeError.message("Invalid ChatGPT sign-in callback.") }
            fields[item.name] = value
        }
        guard fields["state"] == state else { throw TranscribeError.message("ChatGPT sign-in state did not match. Try again.") }
        if fields["error"] != nil { throw TranscribeError.message("ChatGPT sign-in was declined or could not be completed. You can try again in Settings.") }
        guard let code = fields["code"], !code.isEmpty,
              let client = fields["client_id"] ?? account?.clientID,
              !client.isEmpty, client != "dynamic_agent_client",
              account == nil || account?.clientID == client else {
            throw TranscribeError.message("ChatGPT registration was incomplete or changed the selected account.")
        }
        return (code, client)
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let padded = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: padded + String(repeating: "=", count: (4 - padded.count % 4) % 4))
    }
}

public struct ChatGPTIdentity: JWTPayload {
    public var iss: String
    public var sub: String
    public var aud: AudienceClaim
    public var exp: Double
    public var iat: Double
    public var nbf: Double?
    public var nonce: String?
    public var email: String?

    public func verify(using algorithm: some JWTAlgorithm) throws {
        let now = Date().timeIntervalSince1970
        guard iss == "https://auth.openai.com", !sub.isEmpty, exp > now - 5,
              iat <= now + 5, (nbf ?? 0) <= now + 5 else {
            throw TranscribeError.message("ChatGPT returned an expired or invalid identity.")
        }
    }

    public static func validate(_ token: String, jwks: Data, clientID: String, nonce: String?, subject: String? = nil) async throws -> ChatGPTIdentity {
        // Restrict the issuer's published signing algorithm before invoking JWTKit.
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let headerData = Data(base64URL: String(parts[0])),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String,
              let document = try JSONSerialization.jsonObject(with: jwks) as? [String: Any],
              let keys = document["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" &&
                  ($0["alg"] == nil || $0["alg"] as? String == "RS256") && ($0["use"] == nil || $0["use"] as? String == "sig") }) else {
            throw TranscribeError.message("Cannot verify the ChatGPT identity signature.")
        }
        let restricted = try JSONSerialization.data(withJSONObject: ["keys": [key]])
        let collection = try await JWTKeyCollection().add(jwksJSON: String(decoding: restricted, as: UTF8.self))
        let claims = try await collection.verify(token, as: ChatGPTIdentity.self)
        try claims.aud.verifyIntendedAudience(includes: clientID)
        guard nonce == nil || claims.nonce == nonce, subject == nil || claims.sub == subject else {
            throw TranscribeError.message("ChatGPT returned a different identity or sign-in nonce.")
        }
        return claims
    }
}

// One protected document, with independent token records for each client/subject.
// This actor also serializes credential replacement and rotating refreshes.
public actor ChatGPTClient {
    private let service: String
    let session: URLSession
    private var accounts: [ChatGPTAccount]?
    private var refreshes: [String: Task<ChatGPTTokens, Error>] = [:]

    public init(namespace: String, session: URLSession? = nil) {
        service = namespace + ".ChatGPTAccounts"
        self.session = session ?? ChatGPTHTTP.session()
    }

    public func savedAccounts() throws -> [ChatGPTAccount] {
        if let accounts { return accounts }
        var query = vaultQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { accounts = []; return [] }
        guard status == errSecSuccess, let data = result as? Data else { throw TranscribeError.message("Cannot open the ChatGPT account credentials in Keychain (\(status)).") }
        let loaded = try JSONDecoder().decode([ChatGPTAccount].self, from: data)
        accounts = loaded
        return loaded
    }

    private var vaultQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "accounts"]
    }

    private func persist(_ account: ChatGPTAccount) throws {
        var updated = try savedAccounts()
        if let index = updated.firstIndex(where: { $0.id == account.id }) { updated[index] = account }
        else { updated.append(account) }
        let data = try JSONEncoder().encode(updated)
        let query = vaultQuery
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw TranscribeError.message("Cannot save ChatGPT credentials in Keychain (\(status)).") }
        accounts = updated
    }

    public func finishLogin(_ login: ChatGPTLogin, callback: URL) async throws -> ChatGPTAccount {
        let result = try login.callback(callback)
        let data = try await form("token", values: ["grant_type": "authorization_code", "client_id": result.clientID,
            "code": result.code, "code_verifier": login.verifier, "redirect_uri": login.redirectURI, "resource": "https://api.openai.com/v1"])
        let response = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let idToken = response.id_token else { throw TranscribeError.message("ChatGPT did not return a verifiable identity.") }
        let jwks = try await ChatGPTHTTP.data(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/jwks.json")!), session: session)
        let identity: ChatGPTIdentity
        do { identity = try await .validate(idToken, jwks: jwks, clientID: result.clientID, nonce: login.nonce, subject: login.account.flatMap { $0.subject.isEmpty ? nil : $0.subject }) }
        catch { throw TranscribeError.message("ChatGPT identity verification failed. Sign in again; the previous account is kept.") }
        let tokens = try response.tokens(previous: nil)
        let account = ChatGPTAccount(clientID: result.clientID, subject: identity.sub, email: identity.email, tokens: tokens)
        try Task.checkCancellation()
        try persist(account)
        return account
    }

    public func accessToken(for id: String) async throws -> String {
        guard let account = try savedAccounts().first(where: { $0.id == id }), let tokens = account.tokens else {
            throw TranscribeError.message("Continue with ChatGPT in Settings before summarising.")
        }
        guard account.planEnabled else { throw TranscribeError.message("ChatGPT plan usage is not enabled for this connection. Enable it in Settings or choose another provider.") }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        if let refresh = refreshes[id] { return try await refresh.value.accessToken }
        let refresh = Task { try await self.refresh(account) }
        refreshes[id] = refresh
        defer { refreshes[id] = nil }
        return try await refresh.value.accessToken
    }

    private func refresh(_ account: ChatGPTAccount) async throws -> ChatGPTTokens {
        guard let prior = account.tokens, let refreshToken = prior.refreshToken else {
            throw TranscribeError.message("This ChatGPT session needs a new sign-in. Continue with ChatGPT in Settings.")
        }
        let response: TokenResponse
        do {
            let data = try await form("token", values: ["grant_type": "refresh_token", "client_id": account.clientID,
                "refresh_token": refreshToken, "resource": "https://api.openai.com/v1"])
            response = try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch let error as ChatGPTHTTPError {
            if ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(error.code ?? "") {
                var signedOut = account
                signedOut.tokens = nil
                try persist(signedOut)
                throw TranscribeError.message("The ChatGPT session has expired or been disconnected. Sign in again in Settings.")
            }
            throw error
        }
        // Rotating refresh credentials must be saved even if the calling summary was cancelled.
        let tokens = try response.tokens(previous: prior)
        var updated = account
        updated.tokens = tokens
        try persist(updated)
        guard updated.planEnabled else { throw TranscribeError.message("ChatGPT plan permission is no longer enabled. Check Settings.") }
        return tokens
    }

    public func signOut(_ id: String) async throws -> Bool {
        if let pending = refreshes[id] { _ = try? await pending.value }
        guard var account = try savedAccounts().first(where: { $0.id == id }) else { return true }
        var confirmed = account.tokens == nil
        if let refreshToken = account.tokens?.refreshToken {
            // Endpoint from the issuer's discovery document, checked 2026-10-21.
            for attempt in 0..<2 {
                do {
                    let discovery = try await ChatGPTHTTP.data(URLRequest(url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!), session: session)
                    struct Discovery: Decodable { var issuer: String; var revocation_endpoint: URL }
                    let metadata = try JSONDecoder().decode(Discovery.self, from: discovery)
                    let url = metadata.revocation_endpoint
                    guard metadata.issuer == "https://auth.openai.com", url.scheme == "https", url.host == "auth.openai.com",
                          url.user == nil, url.password == nil, url.fragment == nil else { throw TranscribeError.message("Unexpected ChatGPT revocation endpoint.") }
                    _ = try await form("revoke", values: ["token": refreshToken, "token_type_hint": "refresh_token", "client_id": account.clientID], url: url)
                    confirmed = true; break
                }
                catch { if attempt == 0 { try? await Task.sleep(for: .seconds(1)) } }
            }
        }
        account.tokens = nil
        try persist(account)
        return confirmed
    }

    private func form(_ endpoint: String, values: [String: String], url: URL? = nil) async throws -> Data {
        var request = URLRequest(url: url ?? URL(string: "https://auth.openai.com/api/accounts/oauth/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var parts = URLComponents()
        parts.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        return try await ChatGPTHTTP.data(request, session: session)
    }

    struct TokenResponse: Decodable {
        var access_token: String
        var refresh_token: String?
        var id_token: String?
        var token_type: String
        var expires_in: Double
        var scope: String?

        func tokens(previous: ChatGPTTokens?) throws -> ChatGPTTokens {
            guard token_type.lowercased() == "bearer", !access_token.isEmpty, expires_in > 0,
                  previous != nil || scope != nil else { throw TranscribeError.message("ChatGPT returned an incomplete credential response.") }
            return ChatGPTTokens(accessToken: access_token, refreshToken: refresh_token ?? previous?.refreshToken,
                idToken: id_token ?? previous?.idToken, expiresAt: Date().addingTimeInterval(expires_in),
                scopes: scope.map { $0.split(separator: " ").map(String.init) } ?? previous?.scopes ?? [])
        }
    }
}
