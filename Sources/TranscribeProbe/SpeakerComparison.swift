import Foundation
import SpeakerKit
import WhisperKit
import TranscribeCore

enum SpeakerComparison {
    struct Evidence: Codable {
        let speakerCount: Int
        let totalFrames: Int
        let frameRate: Float
        let turns: [TranscriptSegment]
    }
    struct Measurement: Codable {
        let name: String
        let seconds: Double
        let detectedSpeakers: Int
        let sections: Int
        let shortSections: Int
        let unassignedSections: Int
        let speakerSeconds: [String: Double]
    }

    static func run(transcript: URL, models: URL, output: URL, reuseEvidence: URL? = nil) async throws {
        let source = try JSONDecoder().decode(Transcript.self, from: Data(contentsOf: transcript))
        let audio = transcript.deletingLastPathComponent().appendingPathComponent(source.audioFilename)
        if let reuseEvidence,
           output.resolvingSymlinksInPath().standardizedFileURL == reuseEvidence.resolvingSymlinksInPath().standardizedFileURL {
            throw TranscribeError.message("Use a separate output directory to preserve the original evidence.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let variants: [(String, PyannoteDiarizationOptions)] = [
            ("automatic", .init()), ("two-speakers", .init(numberOfSpeakers: 2)),
            ("threshold-0.5", .init(clusterDistanceThreshold: 0.5)),
            ("threshold-0.7", .init(clusterDistanceThreshold: 0.7)),
        ]
        var measurements: [Measurement] = []
        func save(_ value: some Encodable, name: String) throws {
            let url = output.appendingPathComponent(name)
            try Transcript.encoder.encode(value).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        func record(_ result: DiarizationResult, name: String, seconds: Double) throws {
            let attributed = LocalSpeechEngine.attributeSpeakers(in: source, diarization: result)
            let evidence = Evidence(speakerCount: result.speakerCount, totalFrames: result.totalFrames,
                frameRate: result.frameRate, turns: result.segments.map {
                    .init(start: Double($0.startTime), end: Double($0.endTime), text: "", speakerID: $0.speaker.speakerId)
                })
            try save(evidence, name: name + "-turns.json")
            try save(attributed, name: name + "-transcript.json")
            var durations: [String: Double] = [:]
            for turn in evidence.turns { durations[turn.speakerID.map(String.init) ?? "unknown", default: 0] += turn.end - turn.start }
            measurements.append(.init(name: name, seconds: seconds, detectedSpeakers: result.speakerCount,
                sections: attributed.segments.count, shortSections: attributed.segments.filter { $0.text.split(whereSeparator: \.isWhitespace).count <= 2 }.count,
                unassignedSections: attributed.segments.filter { $0.speakerID == nil }.count, speakerSeconds: durations))
            try save(measurements, name: "measurements.json")
            print("\(name): \(result.speakerCount) speakers, \(attributed.segments.count) sections, \(measurements.last!.unassignedSections) unassigned")
        }
        if let reuseEvidence {
            for name in variants.map(\.0) + ["automatic-gap-0.2"] {
                let evidence = try JSONDecoder().decode(Evidence.self, from: Data(contentsOf: reuseEvidence.appendingPathComponent(name + "-turns.json")))
                let result = DiarizationResult(speakerCount: evidence.speakerCount, totalFrames: evidence.totalFrames,
                    frameRate: evidence.frameRate, segments: evidence.turns.map {
                        .init(speaker: $0.speakerID.map(SpeakerInfo.speakerId) ?? .noMatch,
                              startTime: Float($0.start), endTime: Float($0.end), frameRate: evidence.frameRate)
                    })
                try record(result, name: name, seconds: 0)
            }
            return
        }
        let engine = LocalSpeechEngine(models: models)
        guard let folder = try await engine.installation().speakerFolder else {
            throw TranscribeError.message("Prepare speaker models first. This comparison never downloads models.")
        }
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let pipe = try await SpeakerKit(PyannoteConfig(modelFolder: folder, download: false, load: true,
            verbose: false, concurrentSegmenterWorkers: 2, concurrentEmbedderWorkers: 2))
        do {
            for (name, options) in variants {
                try Task.checkCancellation()
                let start = Date()
                var result = try await pipe.diarize(audioArray: samples, options: options)
                let seconds = Date().timeIntervalSince(start)
                try record(result, name: name, seconds: seconds)
                if name == "automatic" {
                    result.updateSegments(minActiveOffset: 0.2)
                    try record(result, name: "automatic-gap-0.2", seconds: seconds)
                }
            }
            await pipe.unloadModels()
        } catch { await pipe.unloadModels(); throw error }
    }
}
