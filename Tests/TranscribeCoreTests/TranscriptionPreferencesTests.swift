import XCTest
@testable import TranscribeCore

final class TranscriptionPreferencesTests: XCTestCase {
    func testLegacyPianissimoMigratesToSwedishOverrideWithMultilingualDefault() throws {
        let preferences = TranscriptionPreferences(legacyModel: .pianissimo)
        XCTAssertEqual(preferences.model(for: "sv"), .pianissimo)
        XCTAssertEqual(preferences.model(for: "auto"), .whisperTurbo)
        XCTAssertEqual(preferences.model(for: "en"), .whisperTurbo)
        XCTAssertEqual(preferences.model(for: "de"), .whisperTurbo)
        XCTAssertEqual(preferences.newRecordingLanguage, "sv")
        let saved = try JSONDecoder().decode(TranscriptionPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(saved, preferences)
    }

    func testFixedLanguageAndRememberLastAreIndependentOfModelRules() {
        var preferences = TranscriptionPreferences()
        preferences.lastSelectedLanguage = "en"
        XCTAssertEqual(preferences.newRecordingLanguage, "en")
        preferences.defaultLanguage = "sv"
        XCTAssertEqual(preferences.newRecordingLanguage, "sv")
        preferences.languageModels["sv"] = .pianissimo
        XCTAssertEqual(preferences.model(for: "en"), .whisperTurbo)
        XCTAssertEqual(preferences.model(for: "sv"), .pianissimo)
        preferences.defaultLanguage = "auto"
        XCTAssertEqual(preferences.newRecordingLanguage, "auto")
        // Incompatible rules cannot send English or Automatic through a Swedish-only engine.
        preferences.languageModels["en"] = .pianissimo
        XCTAssertEqual(preferences.model(for: "en"), .whisperTurbo)
    }
}
