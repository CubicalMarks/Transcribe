import Foundation
import CoreML
import CryptoKit
import FluidAudio

public actor PianissimoEngine: TranscriptionEngine {
    public static let repository = "magnushjelm/pianissimo-sv-coreml"
    public static let revision = "ff8af835072b77a880991ce2d5402d249f923886"
    public static let modelID = repository + "@" + revision
    let directory: URL

    public init(models: URL) {
        // FluidAudio defaults to verbose console logging, including decoded text.
        AppLogger.minimumLevel = .warning
        AppLogger.mirrorsToConsole = false
        directory = models.appendingPathComponent("pianissimo-\(Self.revision)", isDirectory: true)
    }

    public func isPrepared() -> Bool {
        guard let marker = try? String(contentsOf: directory.appendingPathComponent("prepared.txt"), encoding: .utf8),
              marker == Self.modelID else { return false }
        return Self.files.allSatisfy { file in
            let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file.path).path)
            return (attributes?[.size] as? NSNumber)?.int64Value == file.size
        }
    }

    public func prepare(progress: @escaping ProgressHandler) async throws {
        if isPrepared() { return }
        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appendingPathComponent(".pianissimo-download-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for (index, file) in Self.files.enumerated() {
            try Task.checkCancellation()
            await progress(.init("Downloading Pianissimo · file \(index + 1) of \(Self.files.count)…"))
            let url = URL(string: "https://huggingface.co/\(Self.repository)/resolve/\(Self.revision)/\(file.path)")!
            let (temporary, response) = try await session.download(from: url)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw TranscribeError.message("Pianissimo download failed for \(file.path). Try Download & Prepare again.")
            }
            try Self.verify(temporary, file: file)
            let target = stage.appendingPathComponent(file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: target)
        }
        try Task.checkCancellation()
        await progress(.init("Preparing Pianissimo on this Mac…"))
        // Validate the exact local components before publishing readiness. This never
        // calls FluidAudio's stock-model loader or its download/recovery paths.
        try Self.validateModels(at: stage)
        try Task.checkCancellation()
        try Self.modelID.write(to: stage.appendingPathComponent("prepared.txt"), atomically: true, encoding: .utf8)
        let backup = parent.appendingPathComponent(".pianissimo-previous-\(UUID())")
        let existed = fm.fileExists(atPath: directory.path)
        if existed { try fm.moveItem(at: directory, to: backup) }
        do { try fm.moveItem(at: stage, to: directory) }
        catch {
            if existed { try? fm.moveItem(at: backup, to: directory) }
            throw error
        }
        if existed { try? fm.removeItem(at: backup) }
    }

    private static func validateModels(at folder: URL) throws {
        _ = try loadModels(at: folder)
    }

    private static func loadModels(at folder: URL) throws -> AsrModels {
        try AsrModels.loadLocal(from: folder, version: .v3, encoderComputeUnits: .cpuAndGPU)
    }

    public func transcribe(audio: URL, transcript: Transcript, language: String?, progress: @escaping ProgressHandler) async throws -> Transcript {
        guard TranscriptionModel.pianissimo.supports(language: language) else {
            throw TranscribeError.message("Pianissimo is Swedish-only. Choose Swedish, or use Whisper for Automatic, English and mixed recordings.")
        }
        guard isPrepared() else { throw TranscribeError.message("Prepare Pianissimo in Settings → Local Models first.") }
        try Task.checkCancellation()
        await progress(.init("Loading Pianissimo…"))
        let pipe = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1), models: try Self.loadModels(at: directory))
        let reporter = TranscriptionProgressReporter(duration: transcript.duration)
        let delivery = Task { for await update in reporter.updates { await progress(update) } }
        await pipe.setWindowHandler { window in
            reporter.receive([.init(start: window.startSeconds, end: window.endSeconds, text: window.text)])
        }
        do {
            try Task.checkCancellation()
            await progress(.init("Transcribing Swedish with Pianissimo…"))
            var state = try TdtDecoderState()
            let result = try await pipe.transcribe(audio, decoderState: &state)
            reporter.finish()
            await delivery.value
            await pipe.setWindowHandler(nil)
            try Task.checkCancellation()
            let output = try Self.transcript(from: result, original: transcript)
            await pipe.cleanup()
            await progress(.init("Saving transcript…", fraction: 1))
            return output
        } catch {
            reporter.finish()
            await delivery.value
            await pipe.setWindowHandler(nil)
            await pipe.cleanup()
            throw error
        }
    }

    static func transcript(from result: ASRResult, original: Transcript) throws -> Transcript {
        let words = buildWordTimings(from: result.tokenTimings ?? []).map {
            TranscriptSegment(start: $0.startTime, end: $0.endTime, text: $0.word)
        }
        var output = original
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let alignment = WordAlignment(words: words)
        if alignment.covers(text) {
            output.segments = alignment.segments()
            output.alignmentData = try JSONEncoder().encode(alignment)
        } else {
            // Missing/incomplete timing evidence must never discard recognized text.
            output.segments = text.isEmpty ? [] : [.init(start: 0, end: max(0, result.duration), text: text)]
            output.alignmentData = nil
        }
        output.language = "sv"
        output.model = Self.modelID
        output.textEdited = false
        output.speakersIdentified = false
        output.speakerNames = [:]
        output.beforeCleanup = nil
        return output
    }

    struct ModelFile: Sendable {
        let path: String
        let size: Int64
        let sha256: String?
    }

    static func verify(_ url: URL, file: ModelFile) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == file.size else {
            throw TranscribeError.message("Incomplete Pianissimo file: \(file.path). Try Download & Prepare again.")
        }
        if let expected = file.sha256 {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                try Task.checkCancellation()
                hash.update(data: data)
            }
            let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw TranscribeError.message("Pianissimo checksum failed for \(file.path).") }
        }
    }
}
