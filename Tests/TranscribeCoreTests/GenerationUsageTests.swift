import XCTest
@testable import TranscribeCore

final class GenerationUsageTests: XCTestCase {
    func testBothProviderSchemasAndMissingUsage() {
        let details: [String: Any] = ["cached_tokens": 20]
        let reasoning: [String: Any] = ["reasoning_tokens": 30]
        let responses = TokenUsage.parse(["input_tokens": 100, "output_tokens": 50, "total_tokens": 150,
                                         "input_tokens_details": details, "output_tokens_details": reasoning])
        let completions = TokenUsage.parse(["prompt_tokens": 100, "completion_tokens": 50, "total_tokens": 150,
                                           "prompt_tokens_details": details, "completion_tokens_details": reasoning], chatCompletions: true)
        XCTAssertEqual(responses, completions)
        XCTAssertEqual(responses?.input, 100)
        XCTAssertEqual(responses?.output, 50)
        XCTAssertEqual(responses?.total, 150)
        XCTAssertEqual(responses?.cachedInput, 20)
        XCTAssertEqual(responses?.reasoningOutput, 30)
        XCTAssertNil(TokenUsage.parse(nil))
        XCTAssertNil(TokenUsage.parse(["input_tokens": -1, "output_tokens": 2, "total_tokens": 1]))
    }
}
