import XCTest
import Security
import CryptoKit
import JWTKit
@testable import TranscribeCore

private final class ChatGPTProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                var data = Data()
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    data.append(contentsOf: buffer.prefix(n))
                }
                captured.httpBody = data
            }
            let (status, data) = try Self.handler!(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": request.url?.path == "/v1/responses" ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class ChatGPTTests: XCTestCase {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatGPTProtocol.self]
        return URLSession(configuration: config)
    }

    private func signingKey() throws -> JWTKit.Insecure.RSA.PrivateKey {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048] as CFDictionary, nil))
        let data = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, nil)) as Data
        return try JWTKit.Insecure.RSA.PrivateKey(pem: "-----BEGIN RSA PRIVATE KEY-----\n" + data.base64EncodedString(options: .lineLength64Characters) + "\n-----END RSA PRIVATE KEY-----")
    }

    private func jwks(_ key: JWTKit.Insecure.RSA.PrivateKey) throws -> Data {
        let parts = try key.publicKey.getKeyPrimitives()
        return try JSONSerialization.data(withJSONObject: ["keys": [["kty": "RSA", "kid": "fixture", "alg": "RS256", "use": "sig", "n": parts.modulus.base64URL, "e": parts.publicExponent.base64URL]]])
    }

    private func claims(client: String = "fixture-client", nonce: String) -> ChatGPTIdentity {
        ChatGPTIdentity(iss: "https://auth.openai.com", sub: "fixture-subject", aud: .init(value: [client]),
            exp: Date().timeIntervalSince1970 + 3600, iat: Date().timeIntervalSince1970, nbf: nil, nonce: nonce, email: "fictional@example.invalid")
    }

    private func sign(_ claims: ChatGPTIdentity, key: JWTKit.Insecure.RSA.PrivateKey) async throws -> String {
        let collection = await JWTKeyCollection().add(rsa: key, digestAlgorithm: .sha256, kid: "fixture")
        return try await collection.sign(claims, kid: "fixture")
    }

    private func callback(_ login: ChatGPTLogin, client: String = "fixture-client") -> URL {
        var parts = URLComponents(string: login.redirectURI)!
        parts.queryItems = [.init(name: "state", value: login.state), .init(name: "code", value: "synthetic-code"), .init(name: "client_id", value: client)]
        return parts.url!
    }

    func testAuthorizationPKCEAndCallbackBinding() throws {
        let login = try ChatGPTLogin(redirectURI: "http://127.0.0.1:43210/auth/callback", hostID: "urn:uuid:fixture")
        let url = login.authorizationURL()
        let fields = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(fields["client_id"], "dynamic_agent_client")
        XCTAssertEqual(fields["agent_name_hint"], "Transcribe")
        XCTAssertEqual(fields["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(fields["code_challenge"], Data(SHA256.hash(data: Data(login.verifier.utf8))).base64URL)
        XCTAssertTrue(fields["scope"]!.contains("chatgpt.tokens.use.direct"))
        XCTAssertNotEqual(login.state, login.nonce)
        XCTAssertEqual(try login.callback(callback(login)).clientID, "fixture-client")
        for url in ["http://127.0.0.1:43210/auth/callback?state=wrong&code=x&client_id=fixture-client",
                    "http://127.0.0.1:43210/callback?state=\(login.state)&code=x&client_id=fixture-client",
                    "http://localhost:43210/auth/callback?state=\(login.state)&code=x&client_id=fixture-client",
                    "http://127.0.0.1:43210/auth/callback?state=\(login.state)&state=\(login.state)&code=x&client_id=fixture-client",
                    "http://127.0.0.1:43210/auth/callback?state=\(login.state)&error=access_denied",
                    "http://127.0.0.1:43210/auth/callback?state=\(login.state)&code=x&client_id=dynamic_agent_client"] {
            XCTAssertThrowsError(try login.callback(URL(string: url)!))
        }
        let account = ChatGPTAccount(clientID: "original-client", subject: "fixture-subject", email: nil, tokens: nil)
        let returning = try ChatGPTLogin(redirectURI: login.redirectURI, hostID: login.hostID, account: account)
        XCTAssertFalse(returning.authorizationURL().absoluteString.contains("agent_name_hint"))
        XCTAssertThrowsError(try returning.callback(callback(returning, client: "different-client")))
    }

    func testSignedIdentityRejectsWrongIssuerAudienceNonceSubjectAndSignature() async throws {
        let key = try signingKey()
        let keys = try jwks(key)
        let identity = claims(nonce: "expected")
        let token = try await sign(identity, key: key)
        _ = try await ChatGPTIdentity.validate(token, jwks: keys, clientID: "fixture-client", nonce: "expected")
        var invalid: [ChatGPTIdentity] = []
        var wrong = identity; wrong.iss = "https://attacker.invalid"; invalid.append(wrong)
        wrong = identity; wrong.aud = .init(value: ["different-client"]); invalid.append(wrong)
        wrong = identity; wrong.nonce = "wrong"; invalid.append(wrong)
        wrong = identity; wrong.exp = Date().timeIntervalSince1970 - 60; invalid.append(wrong)
        wrong = identity; wrong.sub = "other-person"; invalid.append(wrong)
        for claims in invalid {
            let token = try await sign(claims, key: key)
            do { _ = try await ChatGPTIdentity.validate(token, jwks: keys, clientID: "fixture-client", nonce: "expected", subject: "fixture-subject"); XCTFail("Must reject invalid claims") }
            catch { }
        }
        let other = try signingKey()
        let forged = try await sign(identity, key: other)
        do { _ = try await ChatGPTIdentity.validate(forged, jwks: keys, clientID: "fixture-client", nonce: "expected"); XCTFail("Must reject wrong signature") }
        catch { }
        let unsigned = Data(#"{"alg":"none","kid":"fixture"}"#.utf8).base64URL + "." + Data(#"{"sub":"forged"}"#.utf8).base64URL + "."
        do { _ = try await ChatGPTIdentity.validate(unsigned, jwks: keys, clientID: "fixture-client", nonce: "expected"); XCTFail("Must reject unsigned identity") }
        catch { }
    }

    func testCallbackListenerAcceptsOnlyBoundTransactionAndCancels() async throws {
        let server = ChatGPTCallbackServer()
        let redirect = try await server.start()
        let login = try ChatGPTLogin(redirectURI: redirect, hostID: "urn:uuid:fixture")
        await server.prepare(login)
        let waiting = Task { try await server.wait() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (_, bad) = try await session.data(from: URL(string: redirect + "?state=wrong&code=x&client_id=fixture-client")!)
        XCTAssertEqual((bad as? HTTPURLResponse)?.statusCode, 400)
        let (_, good) = try await session.data(from: callback(login))
        XCTAssertEqual((good as? HTTPURLResponse)?.statusCode, 200)
        let received = try await waiting.value
        XCTAssertEqual(try login.callback(received).code, "synthetic-code")
        let cancelled = ChatGPTCallbackServer()
        _ = try await cancelled.start()
        await cancelled.cancel()
        do { _ = try await cancelled.wait(); XCTFail("Cancelled listener must finish") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testAccountLifecycleRefreshModelCatalogAndStreamingRequest() async throws {
        let namespace = "Transcribe.SyntheticTest." + UUID().uuidString
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: namespace + ".ChatGPTAccounts", kSecAttrAccount as String: "accounts"] as CFDictionary) }
        let session = session()
        defer { session.invalidateAndCancel() }
        let client = ChatGPTClient(namespace: namespace, session: session)
        let login = try ChatGPTLogin(redirectURI: "http://127.0.0.1:43210/auth/callback", hostID: "urn:uuid:fixture")
        let key = try signingKey()
        let keys = try jwks(key)
        let signed = try await sign(claims(nonce: login.nonce), key: key)
        var refreshCount = 0
        var revoked = false
        let responseEvents = [
            #"{"type":"response.output_text.delta","item_id":"fixture-message","output_index":0,"content_index":0,"delta":"Useful "}"#,
            #"{"type":"response.output_text.delta","item_id":"fixture-message","output_index":0,"content_index":0,"delta":"notes."}"#,
            #"{"type":"response.output_text.done","item_id":"fixture-message","output_index":0,"content_index":0,"text":"Useful notes."}"#,
            #"{"type":"response.completed","response":{"status":"completed","output":[]}}"#,
        ]
        let responseBody = Data(responseEvents.map { "data: " + $0 + "\n\n" }.joined().utf8)
        ChatGPTProtocol.handler = { request in
            switch request.url!.path {
            case "/.well-known/jwks.json": return (200, keys)
            case "/.well-known/openid-configuration": return (200, Data(#"{"issuer":"https://auth.openai.com","revocation_endpoint":"https://auth.openai.com/api/accounts/oauth/revoke"}"#.utf8))
            case "/api/accounts/oauth/token":
                let form = String(decoding: request.httpBody!, as: UTF8.self)
                if form.contains("grant_type=authorization_code") {
                    XCTAssertTrue(form.contains("client_id=fixture-client"))
                    XCTAssertTrue(form.contains("code_verifier=" + login.verifier))
                    return (200, try JSONSerialization.data(withJSONObject: ["access_token": "synthetic-initial", "refresh_token": "synthetic-refresh", "id_token": signed, "token_type": "Bearer", "expires_in": 1, "scope": "openid resource.invoke chatgpt.tokens.use.direct offline_access"]))
                }
                refreshCount += 1
                XCTAssertTrue(form.contains("refresh_token=synthetic-refresh"))
                XCTAssertFalse(form.contains("scope="))
                return (200, Data(#"{"access_token":"synthetic-renewed","refresh_token":"synthetic-rotated","token_type":"Bearer","expires_in":3600}"#.utf8))
            case "/v1/models":
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-renewed")
                return (200, Data(#"{"models":[{"slug":"fixture-model","display_name":"Fixture model","visibility":"list"},{"slug":"hidden","display_name":"Hidden","visibility":"hidden"}]}"#.utf8))
            case "/v1/responses":
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(body["model"] as? String, "fixture-model")
                XCTAssertEqual(body["store"] as? Bool, false)
                XCTAssertEqual(body["stream"] as? Bool, true)
                XCTAssertEqual(body["instructions"] as? String, "Summarise")
                XCTAssertNil(body["max_output_tokens"])
                XCTAssertNil(body["audio"])
                return (200, responseBody)
            case "/api/accounts/oauth/revoke":
                revoked = true
                XCTAssertTrue(String(decoding: request.httpBody!, as: UTF8.self).contains("token=synthetic-rotated"))
                return (200, Data())
            default: XCTFail("Unexpected request"); return (500, Data())
            }
        }
        let account = try await client.finishLogin(login, callback: callback(login))
        XCTAssertTrue(account.planEnabled)
        async let first = client.accessToken(for: account.id)
        async let second = client.accessToken(for: account.id)
        let pair = try await (first, second)
        XCTAssertEqual(pair.0, "synthetic-renewed"); XCTAssertEqual(pair.1, pair.0)
        XCTAssertEqual(refreshCount, 1)
        let models = try await client.models(for: account.id)
        XCTAssertEqual(models.map(\.slug), ["fixture-model"])
        let generator = ChatGPTSummaryGenerator(client: client, accountID: account.id, model: models[0].slug, session: session)
        let result = try await generator.generate(instructions: "Summarise", input: "Synthetic text", maxTokens: 900)
        XCTAssertEqual(result, "Useful notes.")
        let restarted = ChatGPTClient(namespace: namespace, session: session)
        let saved = try await restarted.savedAccounts()
        XCTAssertEqual(saved.first?.tokens?.refreshToken, "synthetic-rotated")
        let otherLogin = try ChatGPTLogin(redirectURI: login.redirectURI, hostID: login.hostID)
        var otherClaims = claims(client: "other-client", nonce: otherLogin.nonce)
        otherClaims.sub = "other-subject"
        let otherSigned = try await sign(otherClaims, key: key)
        let originalHandler = ChatGPTProtocol.handler
        ChatGPTProtocol.handler = { request in
            if request.url?.path == "/api/accounts/oauth/token" {
                return (200, try JSONSerialization.data(withJSONObject: ["access_token": "synthetic-other", "refresh_token": "synthetic-other-refresh", "id_token": otherSigned, "token_type": "Bearer", "expires_in": 3600, "scope": "openid email"]))
            }
            return try originalHandler!(request)
        }
        let other = try await client.finishLogin(otherLogin, callback: callback(otherLogin, client: "other-client"))
        XCTAssertFalse(other.planEnabled)
        XCTAssertNotEqual(other.id, account.id)
        XCTAssertNotEqual(other.displayName, account.displayName)
        do { _ = try await client.accessToken(for: other.id); XCTFail("Identity-only consent must not permit inference") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not enabled")) }
        let confirmed = try await client.signOut(account.id)
        XCTAssertTrue(confirmed); XCTAssertTrue(revoked)
        let signedOut = try await client.savedAccounts()
        XCTAssertNil(signedOut.first?.tokens)
        XCTAssertEqual(signedOut.first?.clientID, "fixture-client")
        XCTAssertEqual(signedOut.count, 2)
        XCTAssertNotNil(signedOut.last?.tokens)
    }

    func testRefreshFailureKeepsTemporaryCredentialsAndClearsRevokedTokens() async throws {
        let key = try signingKey()
        let keys = try jwks(key)
        for terminal in [false, true] {
            let namespace = "Transcribe.SyntheticTest." + UUID().uuidString
            defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: namespace + ".ChatGPTAccounts", kSecAttrAccount as String: "accounts"] as CFDictionary) }
            let session = session()
            defer { session.invalidateAndCancel() }
            let client = ChatGPTClient(namespace: namespace, session: session)
            let login = try ChatGPTLogin(redirectURI: "http://127.0.0.1:43210/auth/callback", hostID: "urn:uuid:fixture")
            let signed = try await sign(claims(nonce: login.nonce), key: key)
            ChatGPTProtocol.handler = { request in
                if request.url?.path == "/.well-known/jwks.json" { return (200, keys) }
                let form = String(decoding: request.httpBody!, as: UTF8.self)
                if form.contains("grant_type=authorization_code") {
                    return (200, try JSONSerialization.data(withJSONObject: ["access_token": "synthetic-initial", "refresh_token": "synthetic-refresh", "id_token": signed, "token_type": "Bearer", "expires_in": 1, "scope": "resource.invoke chatgpt.tokens.use.direct offline_access"]))
                }
                return terminal ? (400, Data(#"{"error":"invalid_grant"}"#.utf8)) : (503, Data(#"{"detail":"private-server-detail"}"#.utf8))
            }
            let account = try await client.finishLogin(login, callback: callback(login))
            do { _ = try await client.accessToken(for: account.id); XCTFail("Refresh must fail") }
            catch { XCTAssertFalse(error.localizedDescription.contains("private-server-detail")) }
            let saved = try await client.savedAccounts()
            XCTAssertEqual(saved.first?.tokens == nil, terminal)
            XCTAssertEqual(saved.first?.clientID, account.clientID)
        }
    }

    private static let completedEvent = #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Useful notes."}]}]}}"#

    func testStreamingRejectsPartialFailureRefusalAndMissingCompletion() throws {
        for event in [#"{"type":"response.output_text.delta","delta":"Partial"}"#,
                      #"{"type":"response.incomplete"}"#,
                      #"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"private-detail"}}}"#,
                      #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"no"}]}]}}"#] {
            do {
                var stream = ChatGPTResponseStream()
                try stream.line("data: " + event); try stream.line("")
                _ = try stream.result(); XCTFail("Must reject incomplete or refused stream")
            } catch { XCTAssertFalse(error.localizedDescription.contains("private-detail")) }
        }
        var stream = ChatGPTResponseStream()
        try stream.line(": keepalive")
        try stream.line("data: " + Self.completedEvent)
        XCTAssertEqual(try stream.result(), "Useful notes.")
        var bytes = ChatGPTResponseStream()
        let swedish = Self.completedEvent.replacingOccurrences(of: "Useful notes.", with: "Nästa steg 🙂")
        for byte in Data(("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Nästa\"}\r\n\r\ndata: " + swedish + "\r\n\r\n").utf8) { try bytes.byte(byte) }
        XCTAssertEqual(try bytes.result(), "Nästa steg 🙂")
    }
}
