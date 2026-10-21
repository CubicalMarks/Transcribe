import Foundation
import WhisperKit
import SpeakerKit

public struct EngineProgress: Sendable {
    public var message: String
    public var fraction: Double?
    public var transcription: TranscriptionPreview?
    public init(_ message: String, fraction: Double? = nil, transcription: TranscriptionPreview? = nil) {
        self.message = message; self.fraction = fraction; self.transcription = transcription
    }
}
public typealias ProgressHandler = @Sendable (EngineProgress) async -> Void

public protocol TranscriptionEngine: Sendable {
    func transcribe(audio: URL, transcript: Transcript, language: String?, progress: @escaping ProgressHandler) async throws -> Transcript
}
public protocol SpeakerEngine: Sendable {
    func identifySpeakers(audio: URL, transcript: Transcript, count: Int?, progress: @escaping ProgressHandler) async throws -> Transcript
}

public struct ModelInstallation: Codable, Sendable {
    public var whisperFolder: String?
    public var speakerFolder: String?
}

public actor LocalSpeechEngine: TranscriptionEngine, SpeakerEngine {
    public static let defaultModel = "large-v3-v20240930_626MB"
    public static let languages = Constants.languageCodes.map {
        (name: Locale(identifier: "en").localizedString(forLanguageCode: $0)?.capitalized ?? $0, code: $0)
    }.sorted { $0.name < $1.name }
    public let models: URL
    public let model: String

    public init(models: URL, model: String = LocalSpeechEngine.defaultModel) {
        self.models = models
        self.model = model
    }

    private var manifest: URL { models.appendingPathComponent("installation-\(model).json") }

    public func installation() throws -> ModelInstallation {
        guard FileManager.default.fileExists(atPath: manifest.path) else { return .init() }
        return try JSONDecoder().decode(ModelInstallation.self, from: Data(contentsOf: manifest))
    }

    private func saveInstallation(_ state: ModelInstallation) throws {
        try Transcript.encoder.encode(state).write(to: manifest, options: .atomic)
    }

    public func prepare(speakers: Bool, progress: @escaping ProgressHandler) async throws {
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        var state = try installation()
        if let folder = state.whisperFolder, !FileManager.default.fileExists(atPath: folder) { state.whisperFolder = nil }
        if let folder = state.speakerFolder, !FileManager.default.fileExists(atPath: folder) { state.speakerFolder = nil }
        if state.whisperFolder == nil {
            await progress(.init("Downloading transcription model…"))
            let folder = try await WhisperKit.download(variant: model, downloadBase: models) { value in
                let fraction = value.fractionCompleted
                Task { await progress(.init("Downloading transcription model…", fraction: fraction)) }
            }
            try Task.checkCancellation()
            await progress(.init("Preparing transcription model and tokenizer…"))
            let pipe = try await loadWhisper(folder.path)
            await pipe.unloadModels()
            try Task.checkCancellation()
            state.whisperFolder = folder.path
            try saveInstallation(state)
        }
        if speakers { try await prepareSpeakers(progress: progress) }
    }

    public func prepareSpeakers(progress: @escaping ProgressHandler) async throws {
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        var state = try installation()
        if let folder = state.speakerFolder, !FileManager.default.fileExists(atPath: folder) { state.speakerFolder = nil }
        if state.speakerFolder == nil {
            await progress(.init("Downloading speaker models…"))
            let manager = SpeakerKitDiarizer.pyannote(config: PyannoteConfig(downloadBase: models.path,
                download: true, verbose: false, concurrentSegmenterWorkers: 2, concurrentEmbedderWorkers: 2))
            try await (manager as ModelManager).downloadModels { value in
                let fraction = value.fractionCompleted
                Task { await progress(.init("Downloading speaker models…", fraction: fraction)) }
            }
            guard let folder = manager.modelPath else {
                throw TranscribeError.message("Speaker models could not be prepared.")
            }
            try Task.checkCancellation()
            await progress(.init("Preparing speaker models…"))
            try await manager.loadModels()
            await manager.unloadModels()
            try Task.checkCancellation()
            state.speakerFolder = folder.path
            try saveInstallation(state)
        }
    }

    private func loadWhisper(_ folder: String) async throws -> WhisperKit {
        try await WhisperKit(WhisperKitConfig(modelFolder: folder, tokenizerFolder: models,
            verbose: false, prewarm: false, load: true, download: false))
    }

    public func transcribe(audio: URL, transcript: Transcript, language: String?, progress: @escaping ProgressHandler) async throws -> Transcript {
        guard let folder = try installation().whisperFolder else {
            throw TranscribeError.message("Download the transcription model in Models first.")
        }
        await progress(.init("Loading transcription model…"))
        let pipe = try await loadWhisper(folder)
        let reporter = TranscriptionProgressReporter(duration: transcript.duration)
        let delivery = Task { for await update in reporter.updates { await progress(update) } }
        pipe.segmentDiscoveryCallback = { discovered in
            reporter.receive(discovered.map {
                .init(start: Double($0.start), end: Double($0.end), text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
            })
        }
        do {
            try Task.checkCancellation()
            await progress(.init("Transcribing on this Mac…"))
            // A forced detected-language prompt made Turbo render English turns as
            // Swedish in our mixed fixture. Let Automatic decode its own prompt.
            let options = DecodingOptions(language: language, usePrefillPrompt: language != nil, detectLanguage: false,
                skipSpecialTokens: true, wordTimestamps: true, concurrentWorkerCount: 1, chunkingStrategy: .vad)
            // Incremental decoding bounds conversion memory for longer recordings.
            let results = try await pipe.transcribe(audioPath: audio.path,
                audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                decodeOptions: options, callback: { _ in !Task.isCancelled })
            reporter.finish()
            await delivery.value
            pipe.segmentDiscoveryCallback = nil
            try Task.checkCancellation()
            await progress(.init("Saving transcript…", fraction: 1))
            var output = transcript
            output.segments = results.flatMap(\.segments).map {
                .init(start: Double($0.start), end: Double($0.end), text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }.filter { !$0.text.isEmpty }
            output.language = results.first?.language
            output.model = model
            output.alignmentData = try JSONEncoder().encode(results)
            output.textEdited = false
            output.speakersIdentified = false
            output.speakerNames = [:]
            await pipe.unloadModels()
            return output
        } catch {
            reporter.finish()
            await delivery.value
            pipe.segmentDiscoveryCallback = nil
            await pipe.unloadModels()
            throw error
        }
    }

    public func identifySpeakers(audio: URL, transcript: Transcript, count: Int?, progress: @escaping ProgressHandler) async throws -> Transcript {
        guard let folder = try installation().speakerFolder else {
            throw TranscribeError.message("Download the speaker models in Models first.")
        }
        await progress(.init("Loading speaker models…"))
        let pipe = try await SpeakerKit(PyannoteConfig(modelFolder: folder, download: false, load: true,
            verbose: false, concurrentSegmenterWorkers: 2, concurrentEmbedderWorkers: 2))
        do {
            try Task.checkCancellation()
            await progress(.init("Decoding audio for speaker identification…"))
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
            try Task.checkCancellation()
            await progress(.init("Identifying speakers on this Mac…"))
            let result = try await pipe.diarize(audioArray: samples,
                options: PyannoteDiarizationOptions(numberOfSpeakers: count)) { value in
                let fraction = value.fractionCompleted
                Task { await progress(.init("Identifying speakers on this Mac…", fraction: fraction)) }
            }
            try Task.checkCancellation()
            let output = Self.attributeSpeakers(in: transcript, diarization: result)
            await pipe.unloadModels()
            return output
        } catch {
            await pipe.unloadModels()
            throw error
        }
    }

    static func attributeSpeakers(in transcript: Transcript, diarization result: DiarizationResult) -> Transcript {
        var output = transcript
        if !transcript.textEdited, let data = transcript.alignmentData,
           let alignment = try? JSONDecoder().decode(WordAlignment.self, from: data),
           alignment.covers(transcript.segments.map(\.text).joined()) {
            output.segments = alignment.segments {
                Self.bestSpeaker(start: $0, end: $1, turns: result.segments)
            }
        } else if !transcript.textEdited, let data = transcript.alignmentData,
                  let source = try? JSONDecoder().decode([TranscriptionResult].self, from: data) {
            output.segments = Self.assemble(source: source, diarization: result)
        } else {
            // Never replace edited text when speakers are added or rerun.
            output.segments = transcript.segments.map { segment in
                var updated = segment
                updated.speakerID = Self.bestSpeaker(start: segment.start, end: segment.end, turns: result.segments)
                return updated
            }
        }
        output.speakersIdentified = true
        // Cluster IDs can change on a rerun; old names cannot safely follow them.
        output.speakerNames = [:]
        return output
    }

    public static func assemble(source: [TranscriptionResult], diarization: DiarizationResult) -> [TranscriptSegment] {
        source.flatMap { result in result.segments.flatMap { segment -> [TranscriptSegment] in
            let single = TranscriptionResult(text: segment.text, segments: [segment], language: result.language, timings: .init())
            let aligned = diarization.addSpeakerInfo(to: [single]).flatMap { $0 }
            let alignedText = aligned.map(\.text).joined().filter { !$0.isWhitespace }
            let originalText = segment.text.filter { !$0.isWhitespace }
            if !aligned.isEmpty, alignedText == originalText {
                return aligned.map { .init(start: Double($0.startTime), end: Double($0.endTime),
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), speakerID: $0.speaker.speakerId) }
            }
            // SpeakerKit skips segments without word timings. Keep their text.
            return [.init(start: Double(segment.start), end: Double(segment.end),
                text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines),
                speakerID: bestSpeaker(start: Double(segment.start), end: Double(segment.end), turns: diarization.segments))]
        }}.filter { !$0.text.isEmpty }.sorted { $0.start < $1.start }
    }

    private static func bestSpeaker(start: Double, end: Double, turns: [SpeakerSegment]) -> Int? {
        var overlaps: [Int: Double] = [:]
        for turn in turns {
            guard let id = turn.speaker.speakerId else { continue }
            let overlap = max(0, min(end, Double(turn.endTime)) - max(start, Double(turn.startTime)))
            if overlap > 0 { overlaps[id, default: 0] += overlap }
        }
        return overlaps.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.first?.key
    }
}
