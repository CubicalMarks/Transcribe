import Foundation

public struct TranscriptionPreferences: Codable, Equatable, Sendable {
    public var defaultModel = TranscriptionModel.whisperTurbo
    public var languageModels: [String: TranscriptionModel] = [:]
    /// "last" remembers an explicit choice; "auto" and language codes are fixed defaults.
    public var defaultLanguage = "last"
    public var lastSelectedLanguage = "auto"

    public init(legacyModel: TranscriptionModel? = nil) {
        if legacyModel == .pianissimo {
            languageModels["sv"] = .pianissimo
            lastSelectedLanguage = "sv"
        }
    }

    public var newRecordingLanguage: String {
        defaultLanguage == "last" ? lastSelectedLanguage : defaultLanguage
    }

    public func model(for language: String) -> TranscriptionModel {
        let code: String? = language == "auto" ? nil : language
        if let model = languageModels[language], model.supports(language: code) { return model }
        return defaultModel.supports(language: code) ? defaultModel : .whisperTurbo
    }

    public var configuredModels: Set<TranscriptionModel> {
        Set([defaultModel] + Array(languageModels.values))
    }
}
