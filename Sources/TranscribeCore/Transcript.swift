import Foundation

public struct TranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var speakerID: Int?

    public init(id: UUID = UUID(), start: Double, end: Double, text: String, speakerID: Int? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.speakerID = speakerID
    }
}

public struct Transcript: Identifiable, Codable, Equatable, Sendable {
    public var version = 1
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var audioFilename: String
    public var duration: Double
    public var language: String?
    public var model: String?
    public var segments: [TranscriptSegment] = []
    public var speakerNames: [String: String] = [:]
    public var speakersIdentified = false
    public var textEdited = false
    // Engine-private alignment evidence, separate from the editable transcript.
    public var alignmentData: Data?
    public var summary: RecordingSummary?

    public init(id: UUID = UUID(), title: String, audioFilename: String, duration: Double = 0) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.audioFilename = audioFilename
        self.duration = duration
    }

    public func speakerName(_ id: Int?) -> String {
        guard let id else { return "Unassigned" }
        let name = speakerNames[String(id)]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Speaker \(id + 1)" : name
    }

    public var speakerIDs: [Int] { Array(Set(segments.compactMap(\.speakerID))).sorted() }

    public func exported(as format: ExportFormat) throws -> Data {
        if format == .json {
            // Export the public transcript without the engine's internal evidence.
            var copy = self
            copy.alignmentData = nil
            return try Self.encoder.encode(copy)
        }
        let lines = segments.map { segment in
            let label = speakersIdentified ? "\(speakerName(segment.speakerID)): " : ""
            let prefix = "[\(Self.timestamp(segment.start))] "
            return format == .markdown && !label.isEmpty
                ? "\(prefix)**\(label.trimmingCharacters(in: .whitespaces))**\(label.isEmpty ? "" : " ")\(segment.text)"
                : "\(prefix)\(label)\(segment.text)"
        }
        let title = format == .markdown ? "# \(self.title)\n\n" : "\(self.title)\n\n"
        return Data((title + lines.joined(separator: "\n\n") + "\n").utf8)
    }

    public static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func timestamp(_ seconds: Double) -> String {
        let value = Int(max(0, seconds.isFinite ? seconds : 0))
        if value >= 3600 { return String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

public enum ExportFormat: String, CaseIterable, Sendable {
    case markdown = "md", text = "txt", json
    public var title: String {
        switch self { case .markdown: "Markdown"; case .text: "Plain Text"; case .json: "JSON" }
    }
}

public enum TranscribeError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}
