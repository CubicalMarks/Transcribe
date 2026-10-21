import Foundation
import CryptoKit

public enum SummaryPreset: String, Codable, CaseIterable, Sendable {
    case meetingNotes, brief, actions
    public var title: String {
        switch self { case .meetingNotes: "Meeting notes"; case .brief: "Brief overview"; case .actions: "Action items" }
    }
    public var instruction: String {
        switch self {
        case .meetingNotes: """
            Write detailed meeting notes that someone who missed the conversation can use.
            Start with a short overview of the purpose and outcome. Then use descriptive topic headings and specific bullets under each.
            Cover every substantive topic, including smaller follow-ups near the end. Preserve concrete requirements, workflow steps and ordering,
            rationale, constraints, dependencies, priorities, temporary workarounds, existing/completed work and unresolved choices when discussed.
            Distinguish agreements from suggestions and corrections from superseded proposals. Keep optional details optional; do not settle open questions.
            Capture concrete next steps and handoffs, with owners and deadlines only when explicitly stated. Keep these with their topic when practical.
            End with a short set of key takeaways or follow-ups only if it adds useful synthesis rather than repeating the topic bullets.
            Scale detail to the material: a substantive multi-topic meeting often needs 400–700 words; a short or simple conversation needs less.
            Do not pad to a word target, omit a substantive topic to make the summary short, repeat headings, or create empty template sections.
            """
        case .brief: "Write a short prose overview of the key points and outcome. Keep the summary under 220 words."
        case .actions: "List concrete action items, explicit owners, stated deadlines, and unresolved blockers. Do not turn suggestions into commitments. State when no actions were agreed. Keep the summary under 220 words."
        }
    }

    var outputTokenBudget: Int { self == .meetingNotes ? 2400 : 900 }

    func excerptWordBudget(byteCount: Int) -> Int {
        self == .meetingNotes ? min(600, max(60, byteCount / 16)) : 100
    }
}

public enum SummaryLanguage: String, Codable, CaseIterable, Sendable {
    case source, english, swedish
    public var title: String {
        switch self { case .source: "Source language"; case .english: "English"; case .swedish: "Swedish" }
    }
    public var instruction: String {
        switch self {
        case .source: "Write in the main language of the source material."
        case .english: "Write in English."
        case .swedish: "Write in Swedish."
        }
    }
}

public enum SummaryBackend: String, Codable, CaseIterable, Sendable {
    case onDevice, endpoint, chatGPT
    public var title: String { self == .onDevice ? "On this Mac" : self == .chatGPT ? "ChatGPT plan" : "API endpoint" }
}

public enum SummaryProvider: String, CaseIterable, Sendable {
    case onDevice, chatGPT, openAI, custom
    public var title: String {
        switch self { case .onDevice: "On this Mac"; case .chatGPT: "ChatGPT plan"; case .openAI: "OpenAI API"; case .custom: "Custom API" }
    }
}

public enum SummaryAPIPreset: String, Codable, Sendable { case openAI, custom }

public enum TokenLimitParameter: String, Codable, CaseIterable, Sendable {
    case maxTokens = "max_tokens", maxCompletionTokens = "max_completion_tokens"
}

public struct SummarySettings: Codable, Equatable, Sendable {
    public var backend = SummaryBackend.onDevice
    public var preset = SummaryPreset.meetingNotes
    public var language = SummaryLanguage.source
    public var extraInstructions = ""
    public var baseURL = ""
    public var model = ""
    public var tokenLimitParameter = TokenLimitParameter.maxTokens
    public var maximumOutputTokens: Int? = 4096
    public var apiPreset: SummaryAPIPreset?
    public var chatGPTAccountID: String?
    public var chatGPTModel: String?
    public init() {}

    public var provider: SummaryProvider {
        if backend == .onDevice { return .onDevice }
        if backend == .chatGPT { return .chatGPT }
        return apiPreset == .openAI ? .openAI : .custom
    }

    public mutating func useProvider(_ provider: SummaryProvider) {
        switch provider {
        case .onDevice:
            backend = .onDevice
        case .chatGPT:
            backend = .chatGPT
        case .openAI:
            backend = .endpoint
            apiPreset = .openAI
            baseURL = "https://api.openai.com/v1"
            model = "gpt-5.4-mini"
            tokenLimitParameter = .maxCompletionTokens
            maximumOutputTokens = 4096
        case .custom:
            backend = .endpoint
            apiPreset = .custom
        }
    }

    public func completionURL() throws -> URL {
        guard (900...32768).contains(maximumOutputTokens ?? 4096) else {
            throw TranscribeError.message("Set the API output-token budget between 900 and 32768.")
        }
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.scheme == "https" || (parts.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)) else {
            throw TranscribeError.message("Enter an HTTPS API base URL, without credentials, a query or a fragment. HTTP is allowed only for a loopback server.")
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/chat/completions") { path += "/chat/completions" }
        parts.path = path
        guard let url = parts.url else { throw TranscribeError.message("The API URL is invalid.") }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranscribeError.message("Enter the model identifier used by your API endpoint.")
        }
        return url
    }
}

public struct RecordingSummary: Codable, Equatable, Sendable {
    public var text: String
    public var createdAt: Date
    public var sourceDigest: String
    public var backend: SummaryBackend
    public var model: String
    public var endpointHost: String?
    public var preset: SummaryPreset
    public var language: SummaryLanguage
    public var extraInstructions: String

    public func exported(as format: ExportFormat) throws -> Data {
        if format == .json { return try Transcript.encoder.encode(self) }
        return Data((text + "\n").utf8)
    }
}

extension Transcript {
    public var summarySource: String {
        segments.map { segment in
            let speaker = speakersIdentified ? " \(speakerName(segment.speakerID))" : ""
            return "[\(Self.timestamp(segment.start))]\(speaker): \(segment.text)"
        }.joined(separator: "\n")
    }
    public var summarySourceDigest: String { SHA256.hash(data: Data(summarySource.utf8)).map { String(format: "%02x", $0) }.joined() }
    public var summaryIsOutdated: Bool { summary.map { $0.sourceDigest != summarySourceDigest } ?? false }
}

public enum SummaryChunks {
    // Split on line boundaries where possible; even an unusually long segment
    // is split without dropping Unicode characters or the tail of the transcript.
    public static func split(_ text: String, byteLimit: Int) -> [String] {
        precondition(byteLimit >= 16)
        var chunks: [String] = []
        var current = ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let value = String(line) + (index < lines.count - 1 ? "\n" : "")
            if current.utf8.count + value.utf8.count <= byteLimit { current += value; continue }
            if !current.isEmpty { chunks.append(current); current = "" }
            for scalar in value.unicodeScalars {
                let next = String(scalar)
                if current.utf8.count + next.utf8.count > byteLimit { chunks.append(current); current = "" }
                current += next
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
