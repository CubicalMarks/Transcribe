import XCTest
@testable import TranscribeCore

private actor RecordingGenerator: SummaryTextGenerator {
    nonisolated let inputByteLimit = 100
    var inputs: [String] = []
    func generate(instructions: String, input: String, maxTokens: Int) async throws -> String {
        inputs.append(input)
        return instructions.contains("Extract compact factual notes") ? "Factual notes." : "A complete summary."
    }
}

private final class MockSummaryProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                var body = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
                captured.httpBody = body
            }
            let (status, data) = try Self.handler!(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class SummaryTests: XCTestCase {
    func testProviderPresetKeepsLegacyConfigurationUntilExplicitlyChanged() throws {
        var original = SummarySettings()
        original.backend = .endpoint
        original.baseURL = "https://custom.example/openai/v1"
        original.model = "existing-deployment"
        original.preset = .actions
        original.language = .swedish
        original.extraInstructions = "Focus on deadlines."
        let legacy = try JSONDecoder().decode(SummarySettings.self, from: JSONEncoder().encode(original))
        XCTAssertNil(legacy.apiPreset)
        XCTAssertEqual(legacy.provider, .custom)
        XCTAssertEqual(legacy.model, "existing-deployment")
        var selected = legacy
        selected.useProvider(.onDevice)
        XCTAssertEqual(selected.baseURL, legacy.baseURL)
        selected.useProvider(.custom)
        XCTAssertEqual(selected.model, legacy.model)
        selected.useProvider(.openAI)
        XCTAssertEqual(try selected.completionURL().absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(selected.model, "gpt-5.4-mini")
        XCTAssertEqual(selected.tokenLimitParameter, .maxCompletionTokens)
        XCTAssertEqual(selected.preset, .actions)
        XCTAssertEqual(selected.language, .swedish)
        XCTAssertEqual(selected.extraInstructions, original.extraInstructions)
        let restored = try JSONDecoder().decode(SummarySettings.self, from: JSONEncoder().encode(selected))
        XCTAssertEqual(restored.provider, .openAI)
        selected.useProvider(.chatGPT)
        selected.chatGPTAccountID = "fixture-registration"
        selected.chatGPTModel = "discovered-model"
        let chatGPT = try JSONDecoder().decode(SummarySettings.self, from: JSONEncoder().encode(selected))
        XCTAssertEqual(chatGPT.provider, .chatGPT)
        XCTAssertEqual(chatGPT.model, restored.model)
        XCTAssertEqual(chatGPT.baseURL, restored.baseURL)
        XCTAssertEqual(chatGPT.chatGPTAccountID, "fixture-registration")
    }

    func testLegacyProjectsLoadWithoutSummaryAndSummaryRoundTrips() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var transcript = Transcript(title: "Example", audioFilename: "audio.m4a")
        transcript.segments = [.init(start: 1, end: 4, text: "Hej", speakerID: 0)]
        transcript.speakersIdentified = true
        let legacy = try JSONDecoder().decode(Transcript.self, from: Transcript.encoder.encode(transcript))
        XCTAssertNil(legacy.summary)
        transcript.summary = RecordingSummary(text: "Saved notes", createdAt: Date(), sourceDigest: transcript.summarySourceDigest,
            backend: .onDevice, model: "Local", preset: .meetingNotes, language: .swedish, extraInstructions: "")
        try store.save(transcript)
        XCTAssertEqual(try store.loadAll(), [transcript])
        XCTAssertFalse(transcript.summaryIsOutdated)
        transcript.title = "A new title"
        XCTAssertFalse(transcript.summaryIsOutdated)
        transcript.speakerNames["0"] = "Alice"
        XCTAssertTrue(transcript.summaryIsOutdated)
        XCTAssertEqual(transcript.summary?.text, "Saved notes")
        let exported = try JSONDecoder().decode(Transcript.self, from: transcript.exported(as: .json))
        XCTAssertEqual(exported.summary?.text, "Saved notes")
    }

    func testChunkingRetainsUnicodeAndEntireTailWithinByteBudget() {
        let source = "Första raden 👩🏽‍💻\n" + String(repeating: "åäö🙂", count: 100) + "\nLAST SENTENCE"
        let chunks = SummaryChunks.split(source, byteLimit: 81)
        XCTAssertEqual(chunks.joined(), source)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 81 })
        XCTAssertTrue(chunks.last?.contains("LAST SENTENCE") == true)
    }

    func testLongSourceProcessesAllSectionsBeforeFinalSummary() async throws {
        var transcript = Transcript(title: "Private title", audioFilename: "private-path.m4a")
        transcript.segments = (0..<12).map { .init(start: Double($0), end: Double($0 + 1), text: "Important point \($0). " + String(repeating: "detail ", count: 12)) }
        let generator = RecordingGenerator()
        let result = try await SummaryService.generate(transcript: transcript, settings: SummarySettings(), using: generator, progress: { _ in })
        let inputs = await generator.inputs
        let firstPass = SummaryChunks.split(transcript.summarySource, byteLimit: generator.inputByteLimit)
        XCTAssertEqual(Array(inputs.prefix(firstPass.count)), firstPass)
        XCTAssertTrue(inputs.allSatisfy { $0.utf8.count <= generator.inputByteLimit })
        XCTAssertEqual(result.text, "A complete summary.")
        XCTAssertEqual(result.sourceDigest, transcript.summarySourceDigest)
    }

    func testEndpointValidationAndCanonicalCompletionPath() throws {
        var settings = SummarySettings()
        settings.model = "test-model"
        for invalid in ["http://remote.example/v1", "https://user:key@example.com/v1", "https://example.com/v1?key=secret", "file:///tmp/test", "https://example.com/#fragment"] {
            settings.baseURL = invalid
            XCTAssertThrowsError(try settings.completionURL(), invalid)
        }
        settings.baseURL = "https://example.com/v1/"
        XCTAssertEqual(try settings.completionURL().absoluteString, "https://example.com/v1/chat/completions")
        settings.baseURL = "http://127.0.0.1:9123/v1/chat/completions"
        XCTAssertEqual(try settings.completionURL().path, "/v1/chat/completions")
    }

    func testCompatibleRequestContainsOnlyTextAndUsesSelectedTokenParameter() async throws {
        var settings = SummarySettings()
        settings.backend = .endpoint
        settings.baseURL = "https://example.com/v1"
        settings.model = "configured-model"
        settings.tokenLimitParameter = .maxCompletionTokens
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSummaryProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MockSummaryProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
            let body = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "configured-model")
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 4096)
            XCTAssertNil(body["max_tokens"])
            let messages = body["messages"] as! [[String: String]]
            XCTAssertEqual(messages[1]["content"], "[0:00] Alice: Transcript text")
            XCTAssertNil(body["audio"])
            return (200, Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Summary text"}}]}"#.utf8))
        }
        let generator = EndpointSummaryGenerator(settings: settings, apiKey: "synthetic-test-key", session: session)
        let output = try await generator.generate(instructions: "Summarise", input: "[0:00] Alice: Transcript text", maxTokens: 900)
        XCTAssertEqual(output, "Summary text")
    }

    func testOpenAIWithoutKeyDoesNotSendTranscript() async throws {
        var settings = SummarySettings()
        settings.useProvider(.openAI)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSummaryProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MockSummaryProtocol.handler = { _ in
            XCTFail("Missing OpenAI key must be caught before sending")
            return (401, Data())
        }
        for provider in [SummaryProvider.openAI, .custom] {
            settings.useProvider(provider)
            let generator = EndpointSummaryGenerator(settings: settings, apiKey: "  ", session: session)
            do { _ = try await generator.generate(instructions: "Summarise", input: "Text", maxTokens: 900); XCTFail("Must require a key") }
            catch { XCTAssertTrue(error.localizedDescription.contains("No OpenAI API key is saved")) }
        }
    }

    func testAuthenticationErrorPointsToProviderKeyWithoutExposingResponse() async throws {
        var settings = SummarySettings()
        settings.useProvider(.openAI)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSummaryProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MockSummaryProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-key")
            return (401, Data(#"{"error":{"message":"private-response-detail"}}"#.utf8))
        }
        let generator = EndpointSummaryGenerator(settings: settings, apiKey: " synthetic-key\n", session: session)
        do { _ = try await generator.generate(instructions: "Summarise", input: "Text", maxTokens: 900); XCTFail("Must reject authentication failure") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("rejected authentication (HTTP 401)"))
            XCTAssertTrue(error.localizedDescription.contains("Settings"))
            XCTAssertFalse(error.localizedDescription.contains("token-limit"))
            XCTAssertFalse(error.localizedDescription.contains("synthetic-key"))
            XCTAssertFalse(error.localizedDescription.contains("private-response-detail"))
        }
    }

    func testTruncatedAndRefusedResponsesAreRejected() async throws {
        var settings = SummarySettings()
        settings.baseURL = "https://example.com/v1"
        settings.model = "test"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSummaryProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let generator = EndpointSummaryGenerator(settings: settings, apiKey: "", session: session)
        for body in [#"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#,
                     #"{"choices":[{"finish_reason":"stop","message":{"content":null,"refusal":"no"}}]}"#,
                     #"{"choices":[]}"#] {
            MockSummaryProtocol.handler = { _ in (200, Data(body.utf8)) }
            do { _ = try await generator.generate(instructions: "Summarise", input: "Text", maxTokens: 900); XCTFail("Must reject incomplete/refused output") }
            catch { XCTAssertFalse(error.localizedDescription.contains("partial")) }
        }
    }
}
