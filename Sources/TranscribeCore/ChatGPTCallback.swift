import Foundation
import Network

/// A short-lived OAuth callback bound only to IPv4 loopback, with no remote listener.
public actor ChatGPTCallbackServer {
    private var listener: NWListener?
    private var startWaiter: CheckedContinuation<String, Error>?
    private var callbackWaiter: CheckedContinuation<URL, Error>?
    private var pending: Result<URL, Error>?
    private var login: ChatGPTLogin?
    private var timeout: Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]

    public init() {}

    public func start() async throws -> String {
        try Task.checkCancellation()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { state in Task { await self.stateChanged(state) } }
        listener.newConnectionHandler = { connection in Task { await self.accept(connection) } }
        timeout = Task { try? await Task.sleep(for: .seconds(300)); if !Task.isCancelled { self.finish(.failure(TranscribeError.message("ChatGPT sign-in timed out. Try again in Settings."))) } }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startWaiter = continuation
                listener.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: { Task { await self.cancel() } }
    }

    public func prepare(_ login: ChatGPTLogin) { self.login = login }

    public func wait() async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let pending { continuation.resume(with: pending) }
                else { callbackWaiter = continuation }
            }
        } onCancel: { Task { await self.cancel() } }
    }

    public func cancel() { finish(.failure(CancellationError())) }

    private func stateChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port { startWaiter?.resume(returning: "http://127.0.0.1:\(port.rawValue)/auth/callback"); startWaiter = nil }
        case .failed:
            finish(.failure(TranscribeError.message("Cannot start the local ChatGPT sign-in callback. Try again.")))
        default: break
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard pending == nil else { return }
        pending = result
        callbackWaiter?.resume(with: result); callbackWaiter = nil
        if let startWaiter {
            if case .failure(let error) = result { startWaiter.resume(throwing: error) }
            else { startWaiter.resume(throwing: CancellationError()) }
            self.startWaiter = nil
        }
        listener?.cancel(); listener = nil
        for connection in connections.values { connection.cancel() }
        connections = [:]
        timeout?.cancel(); timeout = nil
    }

    private func accept(_ connection: NWConnection) {
        guard pending == nil, connections.count < 8 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .global(qos: .userInitiated))
        Task {
            let deadline = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { connection.cancel() } }
            defer { deadline.cancel(); connections[id] = nil }
            do {
                var data = Data()
                while data.range(of: Data("\r\n\r\n".utf8)) == nil {
                    let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { content, _, complete, error in
                            if error != nil || (complete && content?.isEmpty != false) { continuation.resume(throwing: CancellationError()) }
                            else { continuation.resume(returning: content ?? Data()) }
                        }
                    }
                    data.append(chunk)
                    guard data.count < 16_384 else { throw CancellationError() }
                }
                let request = String(decoding: data, as: UTF8.self)
                let lines = request.components(separatedBy: "\r\n")
                let first = lines.first?.split(separator: " ").map(String.init) ?? []
                guard first.count == 3, first[0] == "GET", first[1].hasPrefix("/auth/callback?"),
                      let login, let base = URLComponents(string: login.redirectURI),
                      lines.filter({ $0.lowercased().hasPrefix("host:") }).count == 1,
                      lines.contains(where: { $0.lowercased() == "host: 127.0.0.1:\(base.port ?? 0)" }),
                      let url = URL(string: "http://127.0.0.1:\(base.port ?? 0)" + first[1]) else {
                    await reply(connection, status: "400 Bad Request", text: "Unexpected sign-in callback."); return
                }
                // Bad state must not terminate another in-flight sign-in attempt.
                let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "state" } ?? []
                guard state.count == 1, state[0].value == login.state else {
                    await reply(connection, status: "400 Bad Request", text: "Sign-in state did not match."); return
                }
                do {
                    _ = try login.callback(url)
                    await reply(connection, status: "200 OK", text: "Return to Transcribe to finish connecting your ChatGPT account. You can close this tab.")
                    finish(.success(url))
                } catch {
                    await reply(connection, status: "400 Bad Request", text: "Sign-in was not completed. Return to Transcribe.")
                    finish(.failure(error))
                }
            } catch { connection.cancel() }
        }
    }

    private func reply(_ connection: NWConnection, status: String, text: String) async {
        let body = Data(text.utf8)
        let header = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n"
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in connection.cancel(); continuation.resume() })
        }
    }
}
