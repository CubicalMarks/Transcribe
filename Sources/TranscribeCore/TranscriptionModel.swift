import Foundation

public enum TranscriptionModel: String, CaseIterable, Codable, Sendable {
    case whisperTurbo
    case pianissimo

    public var title: String {
        switch self {
        case .whisperTurbo: "Whisper Turbo"
        case .pianissimo: "Pianissimo Swedish (experimental)"
        }
    }

    public var detail: String {
        switch self {
        case .whisperTurbo: "WhisperKit · multilingual · compressed 626 MB variant"
        case .pianissimo: "FluidAudio · Swedish · community Core ML 8-bit conversion · about 632 MB"
        }
    }

    public func supports(language: String?) -> Bool {
        self == .whisperTurbo || language == "sv"
    }
}
