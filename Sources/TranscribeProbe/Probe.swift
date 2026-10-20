import Foundation
import TranscribeCore

@main struct Probe {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.isEmpty {
            print("""
            transcribe-probe --audio FILE --root DIRECTORY [--prepare] [--speakers] [--language sv|en|auto] [--model MODEL]
            Uses a separate local library/cache under DIRECTORY. --prepare explicitly enables model downloads.
            Without --prepare, models must already be installed. Audio/transcripts are never uploaded.
            The tiny model is for development only; the app uses compressed large-v3 Turbo.
            """)
            return
        }
        let known = Set(["--audio", "--root", "--prepare", "--speakers", "--language", "--model"])
        for arg in args where arg.hasPrefix("--") && !known.contains(arg) {
            throw TranscribeError.message("Unknown option: \(arg)")
        }
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") else { return nil }
            return args[index + 1]
        }
        guard let audioPath = value("--audio"), let rootPath = value("--root") else {
            throw TranscribeError.message("--audio and --root are required. Run with --help for usage.")
        }
        let selectedLanguage = value("--language") ?? "auto"
        guard selectedLanguage == "auto" || LocalSpeechEngine.languages.contains(where: { $0.code == selectedLanguage }) else {
            throw TranscribeError.message("Unsupported language: \(selectedLanguage)")
        }
        let store = try TranscriptStore(root: URL(fileURLWithPath: rootPath))
        let engine = LocalSpeechEngine(models: store.models, model: value("--model") ?? LocalSpeechEngine.defaultModel)
        let speakers = args.contains("--speakers")
        let progress: ProgressHandler = { update in
            if update.fraction == nil { FileHandle.standardError.write(Data((update.message + "\n").utf8)) }
        }
        if args.contains("--prepare") { try await engine.prepare(speakers: speakers, progress: progress) }
        let original = try await store.importAudio(URL(fileURLWithPath: audioPath))
        let start = Date()
        let transcript = try await engine.transcribe(audio: store.audioURL(original), transcript: original,
            language: selectedLanguage == "auto" ? nil : selectedLanguage, progress: progress)
        try store.save(transcript)
        var result = transcript
        if speakers {
            result = try await engine.identifySpeakers(audio: store.audioURL(original), transcript: transcript,
                count: nil, progress: progress)
            try store.save(result)
        }
        print(String(data: try result.exported(as: .text), encoding: .utf8) ?? "")
        print("Segments: \(result.segments.count); speakers: \(result.speakerIDs.count); processing seconds: \(String(format: "%.2f", Date().timeIntervalSince(start)))")
        print("Saved: \(store.folder(result.id).path)")
    }
}
