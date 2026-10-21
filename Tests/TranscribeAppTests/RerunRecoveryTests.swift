import XCTest
import AppKit
@testable import TranscribeCore
@testable import Transcribe

@MainActor final class RerunRecoveryAppTests: XCTestCase {
    func testRestoreSavesOneDocumentAtATimeAndRespectsProcessingLock() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "transcribe-rerun-test-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var original = Transcript(title: "Synthetic", audioFilename: "missing.wav")
        original.segments = [.init(start: 0, end: 2, text: "Edited original", speakerID: 1)]
        original.speakerNames = ["1": "Saved name"]
        original.textEdited = true
        let notes = RecordingSummary(text: "Edited notes", createdAt: Date(), sourceDigest: "fixture", backend: .onDevice,
            model: "Synthetic", endpointHost: nil, preset: .meetingNotes, language: .source, extraInstructions: "")
        var current = original
        current.previousTranscription = TranscriptionSnapshot(original)
        current.previousSummary = notes
        current.segments = [.init(start: 0, end: 2, text: "Replacement", speakerID: 0)]
        current.speakerNames = [:]
        try store.save(current)
        let previousRoot = ProcessInfo.processInfo.environment["TRANSCRIBE_LIBRARY_PATH"]
        setenv("TRANSCRIBE_LIBRARY_PATH", root.path, 1)
        let model = AppModel(preferences: preferences)
        if let previousRoot { setenv("TRANSCRIBE_LIBRARY_PATH", previousRoot, 1) } else { unsetenv("TRANSCRIBE_LIBRARY_PATH") }
        model.isBusy = true
        model.restorePreviousResult()
        XCTAssertEqual(try store.loadAll().first, current)
        model.isBusy = false
        model.restorePreviousResult()
        let restored = try XCTUnwrap(store.loadAll().first)
        XCTAssertEqual(restored.segments, original.segments)
        XCTAssertEqual(restored.speakerNames, original.speakerNames)
        XCTAssertNil(restored.previousTranscription)
        XCTAssertEqual(restored.previousSummary, notes)
        model.showSummary = true
        model.restorePreviousResult()
        XCTAssertEqual(model.selected?.summary, notes)
        XCTAssertNil(try store.loadAll().first?.previousSummary)
        XCTAssertEqual(model.selected?.segments, original.segments)
    }
}
