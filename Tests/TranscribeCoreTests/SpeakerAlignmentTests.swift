import XCTest
import SpeakerKit
@testable import TranscribeCore

final class SpeakerAlignmentTests: XCTestCase {
    private func source(_ words: [TranscriptSegment]) throws -> Transcript {
        var transcript = Transcript(title: "Synthetic timing fixture", audioFilename: "audio.wav")
        transcript.segments = words
        transcript.alignmentData = try JSONEncoder().encode(WordAlignment(words: words))
        return transcript
    }

    private func turns(_ segments: [(Double, Double, Int)]) -> DiarizationResult {
        .init(speakerCount: 3, totalFrames: 1000, frameRate: 100, segments: segments.map {
            .init(speaker: .speakerId($0.2), startTime: Float($0.0), endTime: Float($0.1), frameRate: 100)
        })
    }

    func testShortTimingGapMatchesOnlyNearbySpeakerAndKeepsTextAndWordTimes() throws {
        let original = try source([.init(start: 0.8, end: 1, text: "Hej"), .init(start: 1.2, end: 1.5, text: "världen.")])
        let result = LocalSpeechEngine.attributeSpeakers(in: original, diarization: turns([(1.08, 1.6, 2)]))
        XCTAssertEqual(result.segments.map(\.text), ["Hej världen."])
        XCTAssertEqual(result.segments.map(\.speakerID), [2])
        XCTAssertEqual(result.segments.first?.start, 0.8)
        XCTAssertEqual(result.segments.first?.end, 1.5)
        XCTAssertEqual(result.alignmentData, original.alignmentData)
        XCTAssertEqual(original.segments.count, 2)
    }

    func testCompetingNearbySpeakersRemainUnassigned() throws {
        let original = try source([.init(start: 1, end: 1.1, text: "Osäkert")])
        let result = LocalSpeechEngine.attributeSpeakers(in: original, diarization: turns([(0, 0.95, 0), (1.15, 2, 1)]))
        XCTAssertNil(result.segments.first?.speakerID)
        XCTAssertEqual(result.segments.first?.text, "Osäkert")
    }

    func testLongGapsAndLongUnmatchedSpansAreNotFilled() throws {
        for word in [TranscriptSegment(start: 0.8, end: 1, text: "Gap"), .init(start: 0, end: 1, text: "Long span")] {
            let original = try source([word])
            let result = LocalSpeechEngine.attributeSpeakers(in: original, diarization: turns([(1.2, 2, 0)]))
            XCTAssertNil(result.segments.first?.speakerID)
        }
        let long = try source([.init(start: 0, end: 1, text: "Long span")])
        XCTAssertNil(LocalSpeechEngine.attributeSpeakers(in: long, diarization: turns([(1.05, 2, 0)])).segments.first?.speakerID)
    }

    func testActualOverlapWinsAndBriefSpeakerSwitchIsPreserved() throws {
        let original = try source([.init(start: 0.8, end: 1, text: "One"), .init(start: 1, end: 1.2, text: "Two"),
                                   .init(start: 1.2, end: 1.4, text: "Three")])
        let result = LocalSpeechEngine.attributeSpeakers(in: original, diarization: turns([(0, 1, 0), (1, 1.2, 1), (1.2, 2, 0)]))
        XCTAssertEqual(result.segments.map(\.speakerID), [0, 1, 0])
        XCTAssertEqual(result.segments.map(\.text), ["One", "Two", "Three"])
    }

    func testPointTimingInsideSpeechDoesNotBecomeUnassigned() throws {
        let original = try source([.init(start: 1, end: 1, text: "Point")])
        XCTAssertEqual(LocalSpeechEngine.attributeSpeakers(in: original, diarization: turns([(0, 2, 1)])).segments.first?.speakerID, 1)
    }

    func testEditedTextDoesNotUseWordToleranceOrRebuildOldWording() throws {
        var original = try source([.init(start: 0.8, end: 1, text: "Raw wording")])
        original.segments[0].text = "My edited wording"
        original.textEdited = true
        let result = LocalSpeechEngine.attributeSpeakers(in: original, diarization: turns([(1.08, 2, 2)]))
        XCTAssertEqual(result.segments.first?.text, "My edited wording")
        XCTAssertEqual(result.segments.first?.id, original.segments.first?.id)
        XCTAssertNil(result.segments.first?.speakerID)
        XCTAssertEqual(result.alignmentData, original.alignmentData)
    }
}
