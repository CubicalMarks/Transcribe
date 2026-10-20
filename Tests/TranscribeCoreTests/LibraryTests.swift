import XCTest
@testable import TranscribeCore

final class LibraryTests: XCTestCase {
    func testTrashPreservesWholeProjectAndLeavesOtherFilesUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var recording = Transcript(title: "Disposable library fixture", audioFilename: "audio.wav")
        recording.segments = [.init(start: 0, end: 2, text: "Edited notes", speakerID: 0)]
        recording.speakerNames = ["0": "Example speaker"]
        recording.alignmentData = Data([3, 2, 1])
        recording.summary = RecordingSummary(text: "Saved summary", createdAt: Date(), sourceDigest: recording.summarySourceDigest,
            backend: .onDevice, model: "Fixture", preset: .brief, language: .english, extraInstructions: "")
        let other = Transcript(title: "Keep this recording", audioFilename: "audio.wav")
        try store.save(recording)
        try store.save(other)
        let audio = Data("synthetic audio bytes".utf8)
        try audio.write(to: store.audioURL(recording))
        let original = root.appendingPathComponent("imported-original.wav")
        try audio.write(to: original)
        let model = store.models.appendingPathComponent("fixture-model")
        try Data([9]).write(to: model)
        let metadata = try Data(contentsOf: store.folder(recording.id).appendingPathComponent("transcript.json"))

        let trashed = try XCTUnwrap(store.trash(recording.id))
        // Restore this synthetic project before cleanup, including if an assertion fails.
        defer { try? FileManager.default.moveItem(at: trashed, to: store.folder(recording.id)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.folder(recording.id).path))
        XCTAssertEqual(try store.loadAll(), [other])
        XCTAssertEqual(try Data(contentsOf: trashed.appendingPathComponent("transcript.json")), metadata)
        XCTAssertEqual(try Data(contentsOf: trashed.appendingPathComponent("audio.wav")), audio)
        XCTAssertEqual(try Data(contentsOf: original), audio)
        XCTAssertEqual(try Data(contentsOf: model), Data([9]))
        try FileManager.default.moveItem(at: trashed, to: store.folder(recording.id))
        XCTAssertEqual(try store.loadAll().first { $0.id == recording.id }, recording)
    }

    func testFailedTrashLeavesLibraryIntact() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        let recording = Transcript(title: "Retained", audioFilename: "audio.wav")
        try store.save(recording)
        XCTAssertThrowsError(try store.trash(UUID()))
        XCTAssertEqual(try store.loadAll(), [recording])
    }
}
