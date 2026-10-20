import Foundation
import FoundationModels

public struct OnDeviceSummaryGenerator: SummaryTextGenerator {
    public let inputByteLimit = 1_600
    public init() {}

    public static var unavailableReason: String? {
        guard #available(macOS 26, *) else { return "On-device summaries require macOS 26 or later. Use the API endpoint on older macOS versions." }
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return "Enable Apple Intelligence in System Settings to use on-device summaries."
        case .unavailable(.modelNotReady): return "Apple's on-device model is not ready. Allow Apple Intelligence to finish downloading its model."
        case .unavailable(.deviceNotEligible): return "This Mac is not eligible for Apple's on-device language model."
        case .unavailable: return "Apple's on-device language model is currently unavailable."
        }
    }

    public func generate(instructions: String, input: String, maxTokens: Int) async throws -> String {
        if let reason = Self.unavailableReason { throw TranscribeError.message(reason) }
        guard #available(macOS 26, *) else { throw TranscribeError.message("On-device summaries require macOS 26 or later.") }
        try Task.checkCancellation()
        let session = LanguageModelSession(model: .default, instructions: instructions)
        do {
            let response = try await session.respond(to: input, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: maxTokens))
            try Task.checkCancellation()
            return response.content
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            // Do not fall back to an API or transmit source text automatically.
            throw TranscribeError.message("On-device summarisation failed: \(error.localizedDescription). Your saved work is retained. You can choose the API endpoint explicitly.")
        }
    }
}
