import Foundation

/// Provider-neutral word evidence. Saved separately from editable text.
struct WordAlignment: Codable, Sendable {
    let format: String
    let words: [TranscriptSegment]

    init(words: [TranscriptSegment]) {
        format = "transcribe-words-v1"
        self.words = words
    }

    func covers(_ text: String) -> Bool {
        format == "transcribe-words-v1" && !words.isEmpty &&
            words.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } &&
            zip(words, words.dropFirst()).allSatisfy { $0.start <= $1.start } &&
            words.map(\.text).joined().filter { !$0.isWhitespace } == text.filter { !$0.isWhitespace }
    }

    func segments(speaker: (Double, Double) -> Int? = { _, _ in nil }) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        var current: TranscriptSegment?
        for word in words {
            let id = speaker(word.start, word.end)
            if var group = current, group.speakerID == id, word.end - group.start <= 15,
               !group.text.hasSuffix("."), !group.text.hasSuffix("?"), !group.text.hasSuffix("!") {
                group.text += " " + word.text
                group.end = max(group.end, word.end)
                current = group
            } else {
                if let current { result.append(current) }
                current = .init(start: word.start, end: word.end, text: word.text, speakerID: id)
            }
        }
        if let current { result.append(current) }
        return result
    }
}
