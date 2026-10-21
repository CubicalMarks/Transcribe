import Foundation

struct ChatGPTHTTPError: LocalizedError {
    let status: Int
    let code: String?
    let requestID: String?
    var errorDescription: String? {
        let explanation: String
        switch code {
        case "subscription_sharing_user_not_eligible": explanation = "This ChatGPT account or workspace is not eligible to use its plan here."
        case "subscription_sharing_usage_limit_exceeded": explanation = "The ChatGPT usage limit for this request was reached. Review app limits in ChatGPT → Settings → Usage."
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": explanation = "ChatGPT usage is temporarily unavailable. Try again later."
        case "subscription_sharing_unsupported_capability": explanation = "ChatGPT rejected a request capability. Choose another available model or update Transcribe."
        case "subscription_sharing_route_not_supported", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context": explanation = "ChatGPT plan permission or routing was not accepted. Check this connection in Settings."
        default:
            switch status {
            case 401: explanation = "ChatGPT authentication was not accepted. Reconnect the selected account in Settings."
            case 403: explanation = "ChatGPT denied access for this account, workspace or region. Check the connection in Settings."
            case 429: explanation = "ChatGPT is limiting requests. Review ChatGPT → Settings → Usage, or try again later."
            case 500...599: explanation = "ChatGPT is temporarily unavailable. Your connection is kept; try again later."
            default: explanation = "The ChatGPT request could not be completed. Check the connection in Settings."
            }
        }
        return explanation + (status == 200 ? " (stream error" : " (HTTP \(status)") + (code.map { ", \($0)" } ?? "") + ")." + (requestID.map { " Request ID: \($0)." } ?? "") + " No summary was replaced."
    }
}

enum ChatGPTHTTP {
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 180
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    static func error(status: Int, data: Data, requestID: String? = nil) -> ChatGPTHTTPError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? object?["error"] as? String
        let known = ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused", "invalid_client", "subscription_sharing_user_not_eligible", "subscription_sharing_usage_limit_exceeded", "subscription_sharing_usage_unavailable", "subscription_sharing_unsupported_capability", "subscription_sharing_route_not_supported", "subscription_sharing_invalid_user", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context", "subscription_sharing_user_unavailable"]
        let safeID = requestID.flatMap { value in value.count <= 100 && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-.")).contains($0) } ? value : nil }
        return ChatGPTHTTPError(status: status, code: code.flatMap { known.contains($0) ? $0 : nil }, requestID: safeID)
    }

    static func data(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscribeError.message("ChatGPT returned an invalid response.") }
        guard (200..<300).contains(http.statusCode) else { throw error(status: http.statusCode, data: data, requestID: http.value(forHTTPHeaderField: "x-request-id")) }
        return data
    }
}

public struct ChatGPTModel: Decodable, Sendable, Identifiable {
    public var id: String { slug }
    public let slug: String
    public let display_name: String
    let visibility: String?
}

extension ChatGPTClient {
    public func models(for accountID: String) async throws -> [ChatGPTModel] {
        let token = try await accessToken(for: accountID)
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data = try await ChatGPTHTTP.data(request, session: session)
        struct Catalog: Decodable { var models: [ChatGPTModel] }
        let models = try JSONDecoder().decode(Catalog.self, from: data).models.filter { $0.visibility == "list" }
        guard !models.isEmpty else { throw TranscribeError.message("This ChatGPT connection has no available models. Check plan access in Settings.") }
        return models
    }
}

public struct ChatGPTSummaryGenerator: SummaryTextGenerator {
    public let inputByteLimit = 16_000
    private let client: ChatGPTClient
    private let accountID: String
    private let model: String
    private let session: URLSession

    public init(client: ChatGPTClient, accountID: String, model: String, session: URLSession? = nil) {
        self.client = client
        self.accountID = accountID
        self.model = model
        self.session = session ?? ChatGPTHTTP.session()
    }

    func request(token: String, instructions: String, input: String) throws -> URLRequest {
        guard !model.isEmpty else { throw TranscribeError.message("Choose an available ChatGPT model in Settings.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "instructions": instructions,
            "input": [["role": "user", "content": input]], "store": false, "stream": true])
        return request
    }

    public func generate(instructions: String, input: String, maxTokens: Int) async throws -> String {
        try await generateMeasured(instructions: instructions, input: input, maxTokens: maxTokens).text
    }

    public func generateMeasured(instructions: String, input: String, maxTokens: Int) async throws -> GeneratedText {
        let token = try await client.accessToken(for: accountID)
        let request = try request(token: token, instructions: instructions, input: input)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscribeError.message("ChatGPT returned an invalid response.") }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count >= 16_384 { break } }
            throw ChatGPTHTTP.error(status: http.statusCode, data: data, requestID: http.value(forHTTPHeaderField: "x-request-id"))
        }
        var stream = ChatGPTResponseStream(requestID: http.value(forHTTPHeaderField: "x-request-id"))
        // AsyncBytes.lines drops blank lines on macOS. SSE requires those event boundaries.
        for try await byte in bytes { try stream.byte(byte) }
        let text = try stream.result()
        return GeneratedText(text: text, usage: stream.usage)
    }
}

// Do not treat partial output or an ended stream as a successful summary.
struct ChatGPTResponseStream {
    private(set) var usage: TokenUsage?
    private var eventData: [String] = []
    private var eventBytes = 0
    private var completedText: String?
    private struct TextPart: Hashable {
        let output: Int
        let content: Int
    }
    private var streamedParts: [TextPart: String] = [:]
    private var streamedBytes = 0
    private var textEventCount = 0
    private var lineBytes: [UInt8] = []
    private var previousWasCR = false
    private let requestID: String?

    init(requestID: String? = nil) { self.requestID = requestID }

    mutating func byte(_ byte: UInt8) throws {
        if byte == 13 || byte == 10 {
            if byte == 10 && previousWasCR { previousWasCR = false; return }
            try flushLine()
            previousWasCR = byte == 13
        } else {
            previousWasCR = false
            lineBytes.append(byte)
            guard lineBytes.count <= 2_000_000 else { throw TranscribeError.message("ChatGPT returned an oversized stream line.") }
        }
    }

    private mutating func flushLine() throws {
        try Task.checkCancellation()
        guard let text = String(bytes: lineBytes, encoding: .utf8) else { throw TranscribeError.message("ChatGPT returned invalid text encoding.") }
        lineBytes.removeAll(keepingCapacity: true)
        try line(text)
    }

    mutating func line(_ line: String) throws {
        if line.isEmpty { try finishEvent(); return }
        if line.hasPrefix("data:") {
            let data = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            eventBytes += data.utf8.count
            guard eventBytes <= 2_000_000 else { throw TranscribeError.message("ChatGPT returned an oversized event. The previous summary is kept.") }
            eventData.append(data)
        }
    }

    private mutating func finishEvent() throws {
        guard !eventData.isEmpty else { return }
        let data = Data(eventData.joined(separator: "\n").utf8)
        eventData = []; eventBytes = 0
        if String(decoding: data, as: UTF8.self) == "[DONE]" { return }
        guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else {
            throw TranscribeError.message("ChatGPT returned an invalid stream event.")
        }
        if ["response.failed", "error"].contains(type) {
            let response = event["response"] as? [String: Any] ?? event
            let detail = try JSONSerialization.data(withJSONObject: response)
            throw ChatGPTHTTP.error(status: 200, data: detail, requestID: requestID)
        }
        if type == "response.incomplete" { throw TranscribeError.message("ChatGPT returned an incomplete summary. The previous summary is kept.") }
        if type == "response.refusal.delta" || type == "response.refusal.done" {
            throw TranscribeError.message("ChatGPT declined to produce a summary. The previous summary is kept.")
        }
        if type == "response.output_text.delta" || type == "response.output_text.done" {
            guard completedText == nil, let text = event[type.hasSuffix(".delta") ? "delta" : "text"] as? String else {
                throw TranscribeError.message("ChatGPT returned an invalid text stream event.")
            }
            textEventCount += 1
            try store(text, output: event["output_index"] as? Int ?? 0, content: event["content_index"] as? Int ?? 0,
                append: type.hasSuffix(".delta"))
        }
        if type == "response.content_part.done", let part = event["part"] as? [String: Any] {
            if part["type"] as? String == "refusal" { throw TranscribeError.message("ChatGPT declined to produce a summary. The previous summary is kept.") }
            if part["type"] as? String == "output_text", let text = part["text"] as? String {
                try store(text, output: event["output_index"] as? Int ?? 0, content: event["content_index"] as? Int ?? 0)
            }
        }
        if type == "response.output_item.done", let item = event["item"] as? [String: Any] {
            for (index, text) in try assistantParts(item) {
                try store(text, output: event["output_index"] as? Int ?? 0, content: index)
            }
        }
        if type == "response.completed" {
            guard completedText == nil, let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else {
                throw TranscribeError.message("ChatGPT did not confirm completed inference.")
            }
            let output = response["output"] as? [[String: Any]] ?? []
            let finalText = try output.flatMap { try assistantParts($0).map(\.1) }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let streamedText = streamedParts.keys.sorted {
                $0.output == $1.output ? $0.content < $1.content : $0.output < $1.output
            }.compactMap { streamedParts[$0] }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            // A terminal event can be a compact snapshot. Keep the text already
            // delivered through delta/done events, but only after confirmed completion.
            let text = finalText.isEmpty ? streamedText : finalText
            guard !text.isEmpty else {
                let id = requestID.flatMap { $0.count <= 100 && $0.allSatisfy { $0.isLetter || $0.isNumber || "_-".contains($0) } ? $0 : nil }
                throw TranscribeError.message("ChatGPT completed without summary text (\(textEventCount) text events, \(output.count) final output items). Try another available model or try again. The previous summary is kept." + (id.map { " Request ID: \($0)." } ?? ""))
            }
            completedText = text
            usage = TokenUsage.parse(response["usage"])
        }
    }

    private mutating func store(_ text: String, output: Int, content: Int, append: Bool = false) throws {
        guard completedText == nil, output >= 0, content >= 0 else { throw TranscribeError.message("ChatGPT returned an invalid text stream position.") }
        let key = TextPart(output: output, content: content)
        let old = streamedParts[key] ?? ""
        let updated = append ? old + text : text
        streamedBytes += updated.utf8.count - old.utf8.count
        guard streamedBytes <= 2_000_000, streamedParts.count < 4096 || streamedParts[key] != nil else {
            throw TranscribeError.message("ChatGPT returned oversized summary text. The previous summary is kept.")
        }
        streamedParts[key] = updated
    }

    private func assistantParts(_ item: [String: Any]) throws -> [(Int, String)] {
        guard item["type"] as? String == "message", item["role"] as? String == "assistant" else { return [] }
        var texts: [(Int, String)] = []
        for (index, part) in (item["content"] as? [[String: Any]] ?? []).enumerated() {
            if part["type"] as? String == "refusal" { throw TranscribeError.message("ChatGPT declined to produce a summary. The previous summary is kept.") }
            if part["type"] as? String == "output_text", let text = part["text"] as? String { texts.append((index, text)) }
        }
        return texts
    }

    mutating func result() throws -> String {
        if !lineBytes.isEmpty { try flushLine() }
        try finishEvent()
        guard let completedText else { throw TranscribeError.message("The ChatGPT stream ended before completion. The previous summary is kept.") }
        return completedText
    }
}
