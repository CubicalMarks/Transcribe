import XCTest
import FluidAudio
import SpeakerKit
import WhisperKit
@testable import TranscribeCore

final class PianissimoTests: XCTestCase {
    private func result(_ text: String, words: [String]) -> ASRResult {
        .init(text: text, confidence: 1, duration: 10, processingTime: 1,
              tokenTimings: words.enumerated().map { index, word in
                  .init(token: " " + word, tokenId: index, startTime: Double(index),
                        endTime: Double(index) + 0.5, confidence: 1)
              })
    }

    func testPartialTimingsKeepAllTextAndCannotReuseWhisperEvidence() throws {
        var original = Transcript(title: "Fixture", audioFilename: "audio.aiff")
        original.alignmentData = Data("old whisper evidence".utf8)
        original.textEdited = true
        original.speakerNames = ["0": "Old name"]
        let output = try PianissimoEngine.transcript(from: result("Hej hela världen.", words: ["Hej"]), original: original)
        XCTAssertEqual(output.segments.map(\.text), ["Hej hela världen."])
        XCTAssertNil(output.alignmentData)
        XCTAssertEqual(output.model, PianissimoEngine.modelID)
        XCTAssertEqual(output.language, "sv")
        XCTAssertFalse(output.textEdited)
        XCTAssertTrue(output.speakerNames.isEmpty)
        XCTAssertEqual(original.alignmentData, Data("old whisper evidence".utf8))
    }

    func testWordAlignmentSplitsAtSpeakersWithoutLosingTextAndPreservesEdits() throws {
        let original = Transcript(title: "Fixture", audioFilename: "audio.aiff")
        let output = try PianissimoEngine.transcript(from: result("Hej Anna och Johan.", words: ["Hej", "Anna", "och", "Johan."]), original: original)
        XCTAssertEqual(output.segments.map(\.text), ["Hej Anna och Johan."])
        let diarization = DiarizationResult(speakerCount: 2, totalFrames: 500, frameRate: 100, segments: [
            .init(speaker: .speakerId(0), startTime: 0, endTime: 2, frameRate: 100),
            .init(speaker: .speakerId(1), startTime: 2, endTime: 5, frameRate: 100),
        ])
        let attributed = LocalSpeechEngine.attributeSpeakers(in: output, diarization: diarization)
        XCTAssertEqual(attributed.segments.map(\.text), ["Hej Anna", "och Johan."])
        XCTAssertEqual(attributed.segments.map(\.speakerID), [0, 1])
        var edited = output
        edited.segments[0].text = "Min rättade text."
        edited.textEdited = true
        let preserved = LocalSpeechEngine.attributeSpeakers(in: edited, diarization: diarization)
        XCTAssertEqual(preserved.segments.map(\.text), ["Min rättade text."])
        XCTAssertEqual(preserved.alignmentData, edited.alignmentData)
        // Inconsistent or damaged new evidence must also retain the visible text.
        edited.textEdited = false
        XCTAssertEqual(LocalSpeechEngine.attributeSpeakers(in: edited, diarization: diarization).segments.map(\.text), ["Min rättade text."])
        edited.alignmentData = Data("broken".utf8)
        XCTAssertEqual(LocalSpeechEngine.attributeSpeakers(in: edited, diarization: diarization).segments.map(\.text), ["Min rättade text."])
    }

    func testLegacyWhisperAlignmentStillWorks() throws {
        var transcript = Transcript(title: "Old", audioFilename: "audio.wav")
        transcript.segments = [.init(start: 0, end: 3, text: "Saved legacy text")]
        transcript.alignmentData = try JSONEncoder().encode([
            TranscriptionResult(text: "Saved legacy text", segments: [
                .init(start: 0, end: 3, text: "Saved legacy text"),
            ], language: "en", timings: .init()),
        ])
        let diarization = DiarizationResult(speakerCount: 0, totalFrames: 0, frameRate: 100, segments: [])
        let output = LocalSpeechEngine.attributeSpeakers(in: transcript, diarization: diarization)
        XCTAssertEqual(output.segments.map(\.text), transcript.segments.map(\.text))
        XCTAssertEqual(output.segments.first?.start, 0)
        XCTAssertEqual(output.segments.first?.end, 3)
    }

    func testInvalidTimingEvidenceIsNotUsed() {
        XCTAssertFalse(WordAlignment(words: [.init(start: .nan, end: 1, text: "Hej")]).covers("Hej"))
        XCTAssertFalse(WordAlignment(words: [.init(start: 2, end: 3, text: "Hej"), .init(start: 0, end: 1, text: "världen")]).covers("Hej världen"))
    }

    func testModelScopeAndMissingInstallFailBeforeProcessing() async throws {
        XCTAssertTrue(TranscriptionModel.whisperTurbo.supports(language: nil))
        XCTAssertFalse(TranscriptionModel.pianissimo.supports(language: nil))
        XCTAssertFalse(TranscriptionModel.pianissimo.supports(language: "en"))
        XCTAssertTrue(TranscriptionModel.pianissimo.supports(language: "sv"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = PianissimoEngine(models: root)
        let prepared = await engine.isPrepared()
        XCTAssertFalse(prepared)
        let transcript = Transcript(title: "Fixture", audioFilename: "audio.aiff")
        do {
            _ = try await engine.transcribe(audio: root.appendingPathComponent("missing.aiff"), transcript: transcript, language: "sv", progress: { _ in })
            XCTFail("Missing model must fail before opening audio")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Prepare Pianissimo")) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await engine.prepare(progress: { _ in })
        }
        do { try await cancelled.value; XCTFail("Cancelled preparation must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        let readyAfterCancellation = await engine.isPrepared()
        XCTAssertFalse(readyAfterCancellation)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    func testDownloadedWeightVerificationRejectsTruncationAndWrongContent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url)
        let valid = PianissimoEngine.ModelFile(path: "weight.bin", size: 3,
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertNoThrow(try PianissimoEngine.verify(url, file: valid))
        XCTAssertThrowsError(try PianissimoEngine.verify(url, file: .init(path: "weight.bin", size: 4, sha256: nil)))
        try Data("abd".utf8).write(to: url)
        XCTAssertThrowsError(try PianissimoEngine.verify(url, file: valid))
    }
}
