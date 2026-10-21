import XCTest
@testable import TranscribeCore

final class RerunRecoveryTests: XCTestCase {
    private func summary(_ text: String, digest: String = "fixture") -> RecordingSummary {
        .init(text: text, createdAt: Date(timeIntervalSince1970: 100), sourceDigest: digest, backend: .onDevice,
              model: "Synthetic", endpointHost: nil, preset: .meetingNotes, language: .source, extraInstructions: "")
    }

    func testRestoreAvailabilityRequiresADifferentPreviousResult() {
        var current = Transcript(title: "Synthetic", audioFilename: "audio.wav")
        current.segments = [.init(start: 0, end: 2, text: "Saved wording")]
        XCTAssertFalse(current.canRestorePreviousTranscription)
        XCTAssertFalse(current.canRestorePreviousSummary)
        current.previousTranscription = TranscriptionSnapshot(current)
        XCTAssertFalse(current.canRestorePreviousTranscription)
        current.segments[0].text = "New wording"
        XCTAssertTrue(current.canRestorePreviousTranscription)
        XCTAssertFalse(current.restoringPreviousTranscription().canRestorePreviousTranscription)
        current.segments = []
        XCTAssertTrue(current.canRestorePreviousTranscription, "An empty replacement must still be recoverable")
        XCTAssertEqual(current.restoringPreviousTranscription().segments.first?.text, "Saved wording")
        current.summary = summary("Saved notes")
        current.previousSummary = current.summary
        XCTAssertFalse(current.canRestorePreviousSummary)
        current.summary?.text = "New notes"
        XCTAssertTrue(current.canRestorePreviousSummary)
        XCTAssertFalse(current.restoringPreviousSummary().canRestorePreviousSummary)
    }

    func testTranscriptRecoveryRetainsEditsNamesAndEvidenceAcrossRestartWithoutRevertingMetadataOrSummary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var original = Transcript(title: "Original title", audioFilename: "audio.wav", duration: 12)
        original.segments = [.init(start: 1, end: 3, text: "Edited åäö", speakerID: 2)]
        original.speakerNames = ["2": "Saved name"]
        original.speakersIdentified = true
        original.textEdited = true
        original.alignmentData = Data([1, 2, 3])
        original.language = "sv"
        original.model = "Original model"
        original.beforeCleanup = [.init(start: 1, end: 3, text: "Legacy private wording")]
        // The next snapshot must not retain another generation of history.
        original.previousTranscription = TranscriptionSnapshot(Transcript(title: "Older", audioFilename: "audio.wav"))
        var replacement = original
        replacement.previousTranscription = TranscriptionSnapshot(original)
        replacement.segments = [.init(start: 0, end: 12, text: "Replacement", speakerID: 0)]
        replacement.speakerNames = [:]
        replacement.language = "en"
        replacement.model = "New model"
        replacement.textEdited = false
        replacement.beforeCleanup = nil
        replacement.alignmentData = Data([4, 5])
        replacement.summary = summary("New notes")
        replacement.previousSummary = summary("Previous notes")
        replacement.title = "Renamed later"
        replacement.requestedLanguage = "en"
        try store.save(replacement)
        let reopened = try XCTUnwrap(store.loadAll().first)
        let restored = reopened.restoringPreviousTranscription()
        XCTAssertEqual(TranscriptionSnapshot(restored), TranscriptionSnapshot(original))
        XCTAssertNil(restored.previousTranscription)
        XCTAssertEqual(restored.title, replacement.title)
        XCTAssertEqual(restored.requestedLanguage, "en")
        XCTAssertEqual(restored.summary, replacement.summary)
        XCTAssertEqual(restored.previousSummary, replacement.previousSummary)
        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.audioFilename, original.audioFilename)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Transcript.encoder.encode(reopened.previousTranscription)) as? [String: Any])
        XCTAssertNil(object["previousTranscription"], "History is bounded to one result")
    }

    func testSummaryRecoveryPreservesCurrentTranscriptAndIndependentTranscriptBackup() throws {
        var current = Transcript(title: "Synthetic", audioFilename: "audio.wav")
        current.segments = [.init(start: 0, end: 2, text: "Current edited wording")]
        current.textEdited = true
        current.previousTranscription = TranscriptionSnapshot(current)
        current.summary = summary("Replacement summary")
        current.previousSummary = summary("Edited previous summary")
        let reopened = try JSONDecoder().decode(Transcript.self, from: Transcript.encoder.encode(current))
        let restored = reopened.restoringPreviousSummary()
        XCTAssertEqual(restored.summary, current.previousSummary)
        XCTAssertNil(restored.previousSummary)
        XCTAssertEqual(restored.segments, current.segments)
        XCTAssertEqual(restored.previousTranscription, current.previousTranscription)
        XCTAssertTrue(restored.textEdited)
        XCTAssertTrue(restored.summaryIsOutdated)
    }

    func testExportOmitsPrivatePreviousResultsAndOldProjectsHaveNoRecovery() throws {
        var current = Transcript(title: "Synthetic", audioFilename: "audio.wav")
        let legacy = try JSONDecoder().decode(Transcript.self, from: Transcript.encoder.encode(current))
        XCTAssertNil(legacy.previousTranscription)
        XCTAssertNil(legacy.previousSummary)
        current.segments = [.init(start: 0, end: 2, text: "Visible text")]
        current.previousTranscription = TranscriptionSnapshot(current)
        current.previousSummary = summary("Private previous notes")
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: current.exported(as: .json)) as? [String: Any])
        XCTAssertNil(exported["previousTranscription"])
        XCTAssertNil(exported["previousSummary"])
        let publicText = String(decoding: try current.exported(as: .markdown), as: UTF8.self)
        XCTAssertFalse(publicText.contains("Private previous notes"))
        XCTAssertTrue(publicText.contains("Visible text"))
    }
}
