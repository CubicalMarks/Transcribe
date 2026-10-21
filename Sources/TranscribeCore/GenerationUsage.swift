import Foundation

/// Counts reported by the provider, not estimates from the visible text.
public struct TokenUsage: Codable, Equatable, Sendable {
    public let input: Int
    public let output: Int
    public let total: Int
    public let cachedInput: Int?
    public let reasoningOutput: Int?

    static func parse(_ object: Any?, chatCompletions: Bool = false) -> TokenUsage? {
        guard let usage = object as? [String: Any],
              let input = usage[chatCompletions ? "prompt_tokens" : "input_tokens"] as? Int,
              let output = usage[chatCompletions ? "completion_tokens" : "output_tokens"] as? Int,
              let total = usage["total_tokens"] as? Int, input >= 0, output >= 0, total >= 0 else { return nil }
        let inputDetails = usage[chatCompletions ? "prompt_tokens_details" : "input_tokens_details"] as? [String: Any]
        let outputDetails = usage[chatCompletions ? "completion_tokens_details" : "output_tokens_details"] as? [String: Any]
        return TokenUsage(input: input, output: output, total: total,
                          cachedInput: (inputDetails?["cached_tokens"] as? Int).flatMap { $0 >= 0 ? $0 : nil },
                          reasoningOutput: (outputDetails?["reasoning_tokens"] as? Int).flatMap { $0 >= 0 ? $0 : nil })
    }
}

public struct GeneratedText: Sendable {
    public let text: String
    public let usage: TokenUsage?
    public init(text: String, usage: TokenUsage? = nil) { self.text = text; self.usage = usage }
}
