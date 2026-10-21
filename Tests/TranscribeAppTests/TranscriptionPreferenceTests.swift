import XCTest
import AppKit
import TranscribeCore
@testable import Transcribe

@MainActor final class TranscriptionPreferenceTests: XCTestCase {
    func testEachRecordingKeepsItsLanguageAndExplicitChoicesAreRemembered() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "transcribe-preferences-test-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var swedish = Transcript(title: "Swedish fixture", audioFilename: "missing.wav")
        swedish.requestedLanguage = "sv"
        var english = Transcript(title: "English fixture", audioFilename: "missing.wav")
        english.requestedLanguage = "en"
        try store.save(swedish)
        try store.save(english)
        preferences.set(TranscriptionModel.pianissimo.rawValue, forKey: "transcriptionModel")
        let previous = ProcessInfo.processInfo.environment["TRANSCRIBE_LIBRARY_PATH"]
        setenv("TRANSCRIBE_LIBRARY_PATH", root.path, 1)
        let model = AppModel(preferences: preferences)
        if let previous { setenv("TRANSCRIBE_LIBRARY_PATH", previous, 1) } else { unsetenv("TRANSCRIBE_LIBRARY_PATH") }
        model.select(swedish.id)
        XCTAssertEqual(model.language, "sv")
        XCTAssertEqual(model.transcriptionModel, .pianissimo)
        model.select(english.id)
        XCTAssertEqual(model.language, "en")
        XCTAssertEqual(model.transcriptionModel, .whisperTurbo)
        model.language = "auto"
        XCTAssertEqual(model.transcriptionPreferences.newRecordingLanguage, "auto")
        XCTAssertEqual(try store.loadAll().first { $0.id == english.id }?.requestedLanguage, "auto")
        model.transcriptionPreferences.defaultLanguage = "sv"
        XCTAssertEqual(model.transcriptionPreferences.newRecordingLanguage, "sv")
        XCTAssertEqual(model.language, "auto", "Fixed defaults apply to future recordings, not the selected one")
        model.select(swedish.id)
        XCTAssertEqual(model.language, "sv")
        let data = try XCTUnwrap(preferences.data(forKey: "transcriptionPreferences"))
        let saved = try JSONDecoder().decode(TranscriptionPreferences.self, from: data)
        XCTAssertEqual(saved.lastSelectedLanguage, "auto")
        XCTAssertEqual(saved.defaultLanguage, "sv")
        XCTAssertEqual(saved.languageModels["sv"], .pianissimo)
    }
}
