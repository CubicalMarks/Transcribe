import Foundation

/// One previous result, without another generation of history or recording metadata.
public struct TranscriptionSnapshot: Codable, Equatable, Sendable {
    public let segments: [TranscriptSegment]
    public let speakerNames: [String: String]
    public let speakersIdentified: Bool
    public let textEdited: Bool
    public let alignmentData: Data?
    public let language: String?
    public let model: String?
    public let beforeCleanup: [TranscriptSegment]?

    public init(_ transcript: Transcript) {
        segments = transcript.segments
        speakerNames = transcript.speakerNames
        speakersIdentified = transcript.speakersIdentified
        textEdited = transcript.textEdited
        alignmentData = transcript.alignmentData
        language = transcript.language
        model = transcript.model
        beforeCleanup = transcript.beforeCleanup
    }
}

extension Transcript {
    public var canRestorePreviousTranscription: Bool {
        previousTranscription.map { $0 != TranscriptionSnapshot(self) } ?? false
    }

    public var canRestorePreviousSummary: Bool {
        previousSummary.map { $0 != summary } ?? false
    }

    public func restoringPreviousTranscription() -> Transcript {
        guard let previousTranscription else { return self }
        var restored = self
        restored.segments = previousTranscription.segments
        restored.speakerNames = previousTranscription.speakerNames
        restored.speakersIdentified = previousTranscription.speakersIdentified
        restored.textEdited = previousTranscription.textEdited
        restored.alignmentData = previousTranscription.alignmentData
        restored.language = previousTranscription.language
        restored.model = previousTranscription.model
        restored.beforeCleanup = previousTranscription.beforeCleanup
        restored.previousTranscription = nil
        return restored
    }

    public func restoringPreviousSummary() -> Transcript {
        guard let previousSummary else { return self }
        var restored = self
        restored.summary = previousSummary
        restored.previousSummary = nil
        return restored
    }
}
