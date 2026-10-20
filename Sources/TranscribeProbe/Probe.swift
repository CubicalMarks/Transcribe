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

            transcribe-probe --summary-demo [--summary-api BASE_URL --summary-model MODEL]
            Summarises a fixed synthetic meeting. Without --summary-api, uses Apple's on-device model.
            Optional API credential: TRANSCRIBE_SUMMARY_API_KEY environment variable.
            """)
            return
        }
        let known = Set(["--audio", "--root", "--prepare", "--speakers", "--language", "--model", "--summary-demo", "--summary-api", "--summary-model"])
        for arg in args where arg.hasPrefix("--") && !known.contains(arg) {
            throw TranscribeError.message("Unknown option: \(arg)")
        }
        func value(_ flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") else { return nil }
            return args[index + 1]
        }
        if args.contains("--summary-demo") {
            var settings = SummarySettings()
            let generator: any SummaryTextGenerator
            if let endpoint = value("--summary-api") {
                settings.backend = .endpoint
                settings.baseURL = endpoint
                settings.model = value("--summary-model") ?? ""
                _ = try settings.completionURL()
                generator = EndpointSummaryGenerator(settings: settings, apiKey: ProcessInfo.processInfo.environment["TRANSCRIBE_SUMMARY_API_KEY"] ?? "")
            } else { generator = OnDeviceSummaryGenerator() }
            var transcript = Transcript(title: "Synthetic summary fixture", audioFilename: "not-sent.wav")
            transcript.speakersIdentified = true
            transcript.speakerNames = ["0": "Alice", "1": "Bob"]
            transcript.segments = [
                .init(start: 0, end: 8, text: "Let's launch the pilot next Monday. Alice will prepare the invitation by Friday.", speakerID: 0),
                .init(start: 8, end: 18, text: "Agreed. I will check the microphone tomorrow. We have not decided on a budget.", speakerID: 1),
                .init(start: 18, end: 24, text: "Bra, vi testar på måndag. Budgeten är fortfarande en öppen fråga.", speakerID: 0),
            ]
            let result = try await SummaryService.generate(transcript: transcript, settings: settings, using: generator, progress: { _ in })
            print(result.text)
            return
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
