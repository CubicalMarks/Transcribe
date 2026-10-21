import XCTest
@testable import TranscribeCore

final class ChatGPTStreamTests: XCTestCase {
    func testCompletedStreamExposesReportedUsageWithoutMixingItWithText() throws {
        var stream = ChatGPTResponseStream()
        try feed(&stream, #"{"type":"response.output_text.delta","delta":"[]"}"#)
        try feed(&stream, #"{"type":"response.completed","response":{"status":"completed","output":[],"usage":{"input_tokens":100,"output_tokens":50,"total_tokens":150,"output_tokens_details":{"reasoning_tokens":30}}}}"#)
        XCTAssertEqual(try stream.result(), "[]")
        XCTAssertEqual(stream.usage?.input, 100)
        XCTAssertEqual(stream.usage?.reasoningOutput, 30)
    }
    private let compactCompletion = #"{"type":"response.completed","response":{"status":"completed","output":[]}}"#

    private func feed(_ stream: inout ChatGPTResponseStream, _ event: String) throws {
        for byte in Data(("data: " + event + "\r\n\r\n").utf8) { try stream.byte(byte) }
    }

    func testDeltaTextSurvivesCompactCompletionButRequiresCompletion() throws {
        let deltas = [#"{"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"Nästa "}"#,
                      #"{"type":"response.output_text.delta","output_index":0,"content_index":0,"delta":"steg 🙂"}"#]
        var stream = ChatGPTResponseStream()
        for delta in deltas { try feed(&stream, delta) }
        XCTAssertThrowsError(try stream.result())
        try feed(&stream, compactCompletion)
        XCTAssertEqual(try stream.result(), "Nästa steg 🙂")
    }

    func testDoneEventsReplaceDeltasWithoutDuplicateTextAndRespectPartOrder() throws {
        var stream = ChatGPTResponseStream()
        try feed(&stream, #"{"type":"response.output_text.delta","output_index":1,"content_index":0,"delta":"Draft"}"#)
        try feed(&stream, #"{"type":"response.output_text.done","output_index":1,"content_index":0,"text":"Second section"}"#)
        try feed(&stream, #"{"type":"response.content_part.done","output_index":1,"content_index":0,"part":{"type":"output_text","text":"Second section"}}"#)
        try feed(&stream, #"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"First section"}]}}"#)
        try feed(&stream, #"{"type":"response.reasoning_text.done","text":"Private reasoning must not enter notes"}"#)
        try feed(&stream, compactCompletion)
        XCTAssertEqual(try stream.result(), "First section\nSecond section")
    }

    func testFinalSnapshotSupersedesStreamedText() throws {
        var stream = ChatGPTResponseStream()
        try feed(&stream, #"{"type":"response.output_text.delta","delta":"Draft"}"#)
        try feed(&stream, #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Final notes"}]}]}}"#)
        XCTAssertEqual(try stream.result(), "Final notes")
    }

    func testStreamedTextCannotMaskFailureIncompleteOrRefusal() throws {
        let endings = [#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#,
                       #"{"type":"response.incomplete"}"#,
                       #"{"type":"response.refusal.done","refusal":"No"}"#,
                       #"{"type":"response.content_part.done","part":{"type":"refusal","refusal":"No"}}"#,
                       #"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"No"}]}}"#,
                       #"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","role":"assistant","content":[{"type":"refusal","refusal":"No"}]}]}}"#]
        for ending in endings {
            var stream = ChatGPTResponseStream()
            try feed(&stream, #"{"type":"response.output_text.delta","delta":"Partial notes"}"#)
            XCTAssertThrowsError(try feed(&stream, ending))
        }
    }

    func testGenuinelyEmptyResponseHasSafeDiagnostics() throws {
        var stream = ChatGPTResponseStream(requestID: "req_example-123")
        try feed(&stream, #"{"type":"response.reasoning_text.done","text":"Private reasoning"}"#)
        XCTAssertThrowsError(try feed(&stream, compactCompletion)) { error in
            XCTAssertTrue(error.localizedDescription.contains("0 text events, 0 final output items"))
            XCTAssertTrue(error.localizedDescription.contains("req_example-123"))
            XCTAssertFalse(error.localizedDescription.contains("Private reasoning"))
        }
    }
}
