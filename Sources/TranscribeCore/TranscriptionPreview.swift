import Foundation

/// Temporary display data; never written over a saved transcript.
public struct TranscriptionPreview: Sendable {
    public private(set) var segments: [TranscriptSegment] = []
    public private(set) var decodedSeconds: Double = 0
    public let duration: Double

    public init(duration: Double) { self.duration = duration.isFinite ? max(0, duration) : 0 }

    public var fraction: Double? { duration > 0 ? min(1, decodedSeconds / duration) : nil }

    mutating func append(_ discovered: [TranscriptSegment]) -> Bool {
        let valid = discovered.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end >= $0.start }
        guard !valid.isEmpty else { return false }
        segments.append(contentsOf: valid)
        segments.sort { $0.start < $1.start }
        let latest = max(decodedSeconds, valid.map(\.end).max() ?? 0)
        decodedSeconds = duration > 0 ? min(duration, latest) : latest
        return true
    }
}

// SDK callbacks are synchronous. Serialize snapshots into a bounded stream so a
// slower UI cannot queue an unbounded number of preview updates or reorder them.
final class TranscriptionProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var preview: TranscriptionPreview
    private var active = true
    let updates: AsyncStream<EngineProgress>
    private let continuation: AsyncStream<EngineProgress>.Continuation

    init(duration: Double) {
        preview = .init(duration: duration)
        let channel = AsyncStream<EngineProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = channel.stream
        continuation = channel.continuation
    }

    func receive(_ segments: [TranscriptSegment]) {
        lock.withLock {
            guard active, preview.append(segments) else { return }
            let position = Transcript.timestamp(preview.decodedSeconds)
            let message = preview.duration > 0
                ? "Transcribing · through \(position) of \(Transcript.timestamp(preview.duration))"
                : "Transcribing · \(preview.segments.count) sections ready"
            continuation.yield(.init(message, fraction: preview.fraction, transcription: preview))
        }
    }

    func finish() {
        lock.withLock { active = false; continuation.finish() }
    }
}
