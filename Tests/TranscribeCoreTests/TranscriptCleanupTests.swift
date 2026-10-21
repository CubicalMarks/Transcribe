import XCTest
@testable import TranscribeCore

private actor CleanupFixtureGenerator: SummaryTextGenerator {
    nonisolated let inputByteLimit = 400
    let failAfter: Int?
    var inputs: [String] = []
    init(failAfter: Int? = nil) { self.failAfter = failAfter }

    func generate(instructions: String, input: String, maxTokens: Int) async throws -> String {
        inputs.append(input)
        if let failAfter, inputs.count > failAfter { throw TranscribeError.message("Synthetic failure") }
        let entries = try JSONDecoder().decode([TranscriptCleanup.Entry].self, from: Data(input.utf8))
        return try TranscriptCleanup.encode(entries.map {
            .init(id: $0.id, text: $0.text.replacingOccurrences(of: "simple fixture", with: "Simple fixture."))
        })
    }
}

final class TranscriptCleanupTests: XCTestCase {
    func testCleanupApplyRestoreAndExportPreserveEvidenceAndAudioMetadata() async throws {
        var source = Transcript(title: "Synthetic", audioFilename: "audio.wav", duration: 5)
        source.segments = [.init(start: 1, end: 3, text: "simple fixture", speakerID: 2)]
        source.speakerNames = ["2": "Synthetic voice"]
        source.alignmentData = Data([1, 2, 3])
        source.requestedLanguage = "sv"
        let draft = try await TranscriptCleanup.generate(transcript: source, using: CleanupFixtureGenerator(), progress: { _ in })
        XCTAssertEqual(source.segments[0].text, "simple fixture")
        XCTAssertNil(source.beforeCleanup)
        XCTAssertEqual(draft.changedCount, 1)
        let cleaned = try draft.applying(to: source)
        XCTAssertEqual(cleaned.segments[0].text, "Simple fixture.")
        XCTAssertEqual(cleaned.segments[0].id, source.segments[0].id)
        XCTAssertEqual(cleaned.segments[0].speakerID, 2)
        XCTAssertEqual(cleaned.segments[0].start, 1)
        XCTAssertEqual(cleaned.segments[0].end, 3)
        XCTAssertEqual(cleaned.audioFilename, source.audioFilename)
        XCTAssertEqual(cleaned.alignmentData, source.alignmentData)
        XCTAssertTrue(cleaned.textEdited)
        XCTAssertEqual(cleaned.beforeCleanup, source.segments)
        let restoredStorage = try JSONDecoder().decode(Transcript.self, from: Transcript.encoder.encode(cleaned))
        XCTAssertEqual(restoredStorage.beforeCleanup, source.segments)
        let exported = try JSONDecoder().decode(Transcript.self, from: cleaned.exported(as: .json))
        XCTAssertNil(exported.beforeCleanup)
        XCTAssertEqual(exported.segments, cleaned.segments)
        XCTAssertEqual(cleaned.restoringBeforeCleanup().segments, source.segments)
        var changed = source
        changed.segments[0].text = "Edited while reviewing"
        XCTAssertThrowsError(try draft.applying(to: changed))
        changed = source
        changed.segments[0].speakerID = 7
        XCTAssertThrowsError(try draft.applying(to: changed))
    }

    func testLongUnicodeTranscriptIsFullyProcessedWithinEachRequestBound() async throws {
        var source = Transcript(title: "Long synthetic", audioFilename: "missing.wav")
        source.segments = [.init(start: 0, end: 99, text: String(repeating: "Unicode åäö🙂 words. ", count: 300) + "FINAL TOKEN")]
        let generator = CleanupFixtureGenerator()
        let draft = try await TranscriptCleanup.generate(transcript: source, using: generator, progress: { _ in })
        XCTAssertEqual(draft.proposed, source.segments)
        let inputs = await generator.inputs
        XCTAssertGreaterThan(inputs.count, 1)
        XCTAssertTrue(inputs.allSatisfy { $0.utf8.count <= generator.inputByteLimit })
        let sent = try inputs.flatMap { try JSONDecoder().decode([TranscriptCleanup.Entry].self, from: Data($0.utf8)) }.map(\.text).joined()
        XCTAssertEqual(sent, source.segments[0].text)
    }

    func testPartialFailureAndCancellationNeverProduceAnAppliedDraft() async throws {
        var source = Transcript(title: "Failure fixture", audioFilename: "audio.wav")
        source.segments = [.init(start: 0, end: 99, text: String(repeating: "simple fixture ", count: 90))]
        let before = source
        do {
            _ = try await TranscriptCleanup.generate(transcript: source, using: CleanupFixtureGenerator(failAfter: 1), progress: { _ in })
            XCTFail("A partial response must not succeed")
        } catch { XCTAssertEqual(error.localizedDescription, "Synthetic failure") }
        XCTAssertEqual(source, before)
        let generator = CleanupFixtureGenerator()
        let snapshot = source
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await TranscriptCleanup.generate(transcript: snapshot, using: generator, progress: { _ in })
        }
        do { _ = try await task.value; XCTFail("Cancellation must stop cleanup") }
        catch { XCTAssertTrue(error is CancellationError) }
        let inputs = await generator.inputs
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertEqual(source, before)
    }

    func testMissingDuplicateInventedAndEmptySectionsAreRejected() throws {
        let expected = [TranscriptCleanup.Entry(id: "0:0", text: "Hej"), .init(id: "1:0", text: "världen")]
        for entries in [Array(expected.prefix(1)), [expected[0], expected[0]],
                        [expected[0], .init(id: "invented", text: "new")],
                        [expected[0], .init(id: "1:0", text: " ")]] {
            XCTAssertThrowsError(try TranscriptCleanup.parse(TranscriptCleanup.encode(entries), expected: expected, byteLimit: 2000))
        }
        XCTAssertThrowsError(try TranscriptCleanup.parse("Not JSON", expected: expected, byteLimit: 2000))
        let valid = "```json\n" + (try TranscriptCleanup.encode(Array(expected.reversed()))) + "\n```"
        XCTAssertEqual(try TranscriptCleanup.parse(valid, expected: expected, byteLimit: 2000).count, 2)
    }

    func testJoinRetainsWordsTimeSpanAndPreviousSpeaker() throws {
        var source = Transcript(title: "Join fixture", audioFilename: "audio.wav")
        source.segments = [.init(start: 1, end: 3, text: "First part", speakerID: 0), .init(start: 3.5, end: 6, text: "second part", speakerID: 1)]
        let output = try source.joiningWithPrevious(source.segments[1].id)
        XCTAssertEqual(output.segments.count, 1)
        XCTAssertEqual(output.segments[0].text, "First part second part")
        XCTAssertEqual(output.segments[0].start, 1)
        XCTAssertEqual(output.segments[0].end, 6)
        XCTAssertEqual(output.segments[0].speakerID, 0)
        XCTAssertTrue(output.textEdited)
        XCTAssertEqual(source.segments.count, 2)
        XCTAssertThrowsError(try source.joiningWithPrevious(source.segments[0].id))
    }
}
