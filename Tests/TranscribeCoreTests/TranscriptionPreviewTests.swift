import XCTest
@testable import TranscribeCore

final class TranscriptionPreviewTests: XCTestCase {
    func testNewestBufferedUpdateContainsAllSectionsAndIgnoresLateCallbacks() async throws {
        let reporter = TranscriptionProgressReporter(duration: 60)
        for i in 0..<100 {
            reporter.receive([.init(start: Double(i) / 2, end: Double(i + 1) / 2, text: "Avsnitt \(i) 🙂")])
        }
        reporter.finish()
        reporter.receive([.init(start: 50, end: 60, text: "Late callback must not escape")])
        var updates: [EngineProgress] = []
        for await update in reporter.updates { updates.append(update) }
        XCTAssertEqual(updates.count, 1)
        let preview = try XCTUnwrap(updates.first?.transcription)
        XCTAssertEqual(preview.segments.count, 100)
        XCTAssertEqual(preview.segments.last?.text, "Avsnitt 99 🙂")
        XCTAssertEqual(preview.decodedSeconds, 50)
        XCTAssertEqual(try XCTUnwrap(updates.first?.fraction), 50.0 / 60, accuracy: 0.0001)
    }

    func testAudioPositionIsMonotonicBoundedAndUnknownDurationStaysIndeterminate() {
        var preview = TranscriptionPreview(duration: 30)
        XCTAssertTrue(preview.append([.init(start: 10, end: 20, text: "Later section")]))
        XCTAssertTrue(preview.append([.init(start: 0, end: 8, text: "Earlier section")]))
        XCTAssertEqual(preview.segments.map(\.text), ["Earlier section", "Later section"])
        XCTAssertEqual(preview.decodedSeconds, 20)
        XCTAssertFalse(preview.append([.init(start: 20, end: .nan, text: "Invalid"), .init(start: 20, end: 25, text: " "), .init(start: -1, end: 30, text: "Invalid")]))
        XCTAssertEqual(preview.segments.count, 2)
        XCTAssertEqual(preview.decodedSeconds, 20)
        XCTAssertTrue(preview.append([.init(start: 20, end: 32, text: "Timestamp beyond audio duration")]))
        XCTAssertEqual(preview.decodedSeconds, 30)
        XCTAssertEqual(preview.fraction, 1)
        var unknown = TranscriptionPreview(duration: .nan)
        XCTAssertTrue(unknown.append([.init(start: 0, end: 5, text: "Text")]))
        XCTAssertNil(unknown.fraction)
        XCTAssertEqual(unknown.decodedSeconds, 5)
    }
}
