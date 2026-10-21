import Foundation
import TranscribeCore

private actor MeasuredGenerator: SummaryTextGenerator {
    nonisolated let inputByteLimit: Int
    let base: any SummaryTextGenerator
    struct Call: Codable {
        let seconds: Double
        let inputBytes: Int
        let outputBytes: Int
        let usage: TokenUsage?
    }
    var calls: [Call] = []
    init(_ base: any SummaryTextGenerator) { self.base = base; inputByteLimit = base.inputByteLimit }
    func generate(instructions: String, input: String, maxTokens: Int) async throws -> String {
        let start = Date()
        let result = try await base.generateMeasured(instructions: instructions, input: input, maxTokens: maxTokens)
        calls.append(Call(seconds: Date().timeIntervalSince(start), inputBytes: instructions.utf8.count + input.utf8.count,
                          outputBytes: result.text.utf8.count, usage: result.usage))
        return result.text
    }
}

enum CleanupProbe {
    // Entirely invented, with explicit numbers, uncertainty, names, code-switching,
    // repeated words and short same/unknown/different-speaker sections.
    static let fixtures: [(String, [String])] = [
        ("swedish", [
            "vi testar utställningen på måndag och jag tror att entrén öppnar klockan 9",
            "men vi har inte bestämt budgeten än den är inte 15000 kronor det är bara ett förslag",
            "Röda Korset har inte bekräftat något och namnet Zylvra ska stå kvar precis så",
            "jag jag menar att Sara kanske kan kontrollera mikrofonen men vi har inte frågat henne",
            "ja vi behöver också två skyltar en vid dörren och en vid hissen",
            "det är viktigt att det står 12 oktober på inbjudan inte 21 oktober",
            "eh",
            "vi kan vänta till torsdag om det behövs men det är inget beslut",
            "och om leveransen inte kommer då",
        ]),
        ("english", [
            "We haven't approved the budget. The figure of 15,000 SEK is only a suggestion.",
            "The doors open at 9:30 on 12 October. Please keep the name Zylvra exactly as written.",
            "Sara might check the microphone, but nobody has asked her yet.",
            "we we need two signs one by the door and another by the lift",
            "I don't want to cancel the trial. I want to postpone the invitation until Thursday.",
            "that's a suggestion not an agreed deadline and if the delivery doesn't arrive then",
            "um",
            "Let's leave that question open. No owner has been assigned.",
        ]),
        ("mixed", [
            "vi behöver en staging environment men production får inte ändras",
            "The release is not approved. We might test it on Friday, if the backup is ready.",
            "AboveSeven och Shopify ska behålla sina namn och versionen är 2.4.1",
            "ja ja och Röda Korset har inte sagt ja till något ännu",
            "we should keep the action items in Swedish om det är så vi sa det",
            "priset är 2100 kronor per år inte per månad och det är fortfarande bara ett exempel",
            "hur",
            "ska vi göra om backupen saknas det har vi inte bestämt",
            "I think we should wait, but that's just my opinion.",
        ]),
    ]

    static func run(output: String) async throws {
        // Explicit command only; never walks the recording library or prints credentials.
        let namespace = "se.marcusliback.Transcribe"
        guard let data = UserDefaults(suiteName: namespace)?.data(forKey: "summarySettings") else {
            throw TranscribeError.message("No saved app text settings were found.")
        }
        let settings = try JSONDecoder().decode(SummarySettings.self, from: data)
        let base: any SummaryTextGenerator
        let model: String
        switch settings.backend {
        case .chatGPT:
            guard let account = settings.chatGPTAccountID, let selected = settings.chatGPTModel, !selected.isEmpty else {
                throw TranscribeError.message("Select a ChatGPT connection/model in the app first.")
            }
            base = ChatGPTSummaryGenerator(client: ChatGPTClient(namespace: namespace), accountID: account, model: selected)
            model = selected
        case .onDevice:
            base = OnDeviceSummaryGenerator()
            model = "Apple on-device"
        case .endpoint:
            throw TranscribeError.message("This probe uses the saved ChatGPT or on-device connection. API benchmark credentials are not loaded automatically.")
        }
        struct Run: Codable {
            let fixture: String
            let seconds: Double
            let original: [TranscriptSegment]
            let cleaned: [TranscriptSegment]
            let calls: [MeasuredGenerator.Call]
        }
        struct Report: Codable { let date: Date; let model: String; let runs: [Run] }
        var runs: [Run] = []
        for (name, texts) in fixtures {
            var transcript = Transcript(title: "Synthetic \(name)", audioFilename: "not-read.wav")
            transcript.segments = texts.enumerated().map { index, text in
                .init(start: Double(index * 6), end: Double(index * 6 + 6), text: text,
                      speakerID: index == 6 ? nil : (index < 4 ? 0 : 1))
            }
            let generator = MeasuredGenerator(base)
            let start = Date()
            let result = try await TranscriptCleanup.generate(transcript: transcript, using: generator, progress: { _ in })
            runs.append(Run(fixture: name, seconds: Date().timeIntervalSince(start), original: transcript.segments,
                            cleaned: result.proposed, calls: await generator.calls))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Report(date: Date(), model: model, runs: runs)).write(to: URL(fileURLWithPath: output), options: .atomic)
            print("\(name): \(String(format: "%.2f", runs.last!.seconds)) s; \(runs.last!.calls.count) requests; usage saved in report")
        }
    }
}
