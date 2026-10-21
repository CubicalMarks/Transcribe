import XCTest
import WhisperKit
import SpeakerKit
@testable import TranscribeCore

final class TranscriptTests: XCTestCase {
    func testPartialWordTimingsCannotDeleteTranscriptionText() {
        let source = TranscriptionResult(text: "Hello whole sentence", segments: [
            .init(start: 0, end: 4, text: "Hello whole sentence", words: [
                .init(word: "Hello", tokens: [], start: 0, end: 1, probability: 1),
            ]),
        ], language: "en", timings: .init())
        let diarization = DiarizationResult(speakerCount: 1, totalFrames: 500, frameRate: 100,
            segments: [.init(speaker: .speakerId(0), startTime: 0, endTime: 5, frameRate: 100)])
        let result = LocalSpeechEngine.assemble(source: [source], diarization: diarization)
        XCTAssertEqual(result.map(\.text), ["Hello whole sentence"])
    }

    func testSpeakerAlignmentKeepsTextWithoutWordTimings() {
        let source = TranscriptionResult(text: "Hej världen", segments: [
            .init(start: 1, end: 3, text: "Hej världen", words: nil),
        ], language: "sv", timings: .init())
        let diarization = DiarizationResult(speakerCount: 1, totalFrames: 300, frameRate: 100,
            segments: [.init(speaker: .speakerId(0), startTime: 0, endTime: 4, frameRate: 100)])
        let result = LocalSpeechEngine.assemble(source: [source], diarization: diarization)
        XCTAssertEqual(result.map(\.text), ["Hej världen"])
        XCTAssertEqual(result.first?.speakerID, 0)
        XCTAssertEqual(result.first?.start, 1)
    }

    func testAlignmentKeepsUnmatchedSpeech() {
        let source = TranscriptionResult(text: "Unmatched speech", segments: [
            .init(start: 8, end: 9, text: "Unmatched speech"),
        ], language: "en", timings: .init())
        let diarization = DiarizationResult(speakerCount: 0, totalFrames: 0, frameRate: 100, segments: [])
        let result = LocalSpeechEngine.assemble(source: [source], diarization: diarization)
        XCTAssertEqual(result.first?.text, "Unmatched speech")
        XCTAssertNil(result.first?.speakerID)
    }

    func testStoreRoundTripRetainsEditsNamesAndEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var transcript = Transcript(title: "Meeting", audioFilename: "audio.m4a")
        transcript.segments = [.init(start: 3601, end: 3604, text: "Edited Swedish: åäö", speakerID: 2)]
        transcript.speakerNames = ["2": "Marcus"]
        transcript.speakersIdentified = true
        transcript.textEdited = true
        transcript.alignmentData = Data([1, 2, 3])
        transcript.beforeCleanup = [.init(start: 3601, end: 3604, text: "Legacy original wording", speakerID: 2)]
        try store.save(transcript)
        XCTAssertEqual(try store.loadAll(), [transcript])
        var saved = try XCTUnwrap(store.loadAll().first)
        saved.title = "Renamed after removing cleanup"
        try store.save(saved)
        XCTAssertEqual(try store.loadAll().first?.beforeCleanup, transcript.beforeCleanup)
        XCTAssertEqual(try store.loadAll().first?.segments, transcript.segments)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.folder(transcript.id).appendingPathComponent("transcript.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
        let text = String(decoding: try transcript.exported(as: .text), as: UTF8.self)
        XCTAssertTrue(text.contains("[1:00:01] Marcus: Edited Swedish: åäö"))
        let json = try JSONDecoder().decode(Transcript.self, from: transcript.exported(as: .json))
        XCTAssertNil(json.alignmentData)
        XCTAssertNil(json.beforeCleanup)
        XCTAssertEqual(json.segments, transcript.segments)
    }

    func testInvalidAudioPathCannotEscapeProject() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        let invalid = Transcript(title: "Invalid", audioFilename: "../../outside.m4a")
        XCTAssertThrowsError(try store.save(invalid))
    }

    func testMarkdownWithoutSpeakersHasNoEmptyBoldMarkup() throws {
        var transcript = Transcript(title: "Example", audioFilename: "audio.wav")
        transcript.segments = [.init(start: 0, end: 2, text: "Hello")]
        let markdown = String(decoding: try transcript.exported(as: .markdown), as: UTF8.self)
        XCTAssertTrue(markdown.contains("[0:00] Hello"))
        XCTAssertFalse(markdown.contains("****"))
    }
}
