import XCTest
import SwiftUI
import AppKit
import TranscribeCore
@testable import Transcribe

@MainActor final class DocumentLayoutPerformanceTests: XCTestCase {
    func testDocumentScrollLayout() throws { try exerciseScroll(rapid: false) }

    func testRapidScrollAcrossFullDocument() throws { try exerciseScroll(rapid: true) }

    private func exerciseScroll(rapid: Bool) throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TranscriptStore(root: root)
        var transcript = Transcript(title: "Synthetic performance fixture", audioFilename: "missing.wav", duration: 700)
        transcript.speakersIdentified = true
        transcript.segments = (0..<224).map { index in
            .init(start: Double(index * 3), end: Double(index * 3 + 3),
                text: "Section \(index). " + String(repeating: "Synthetic discussion åäö. ", count: index % 6 + 1), speakerID: index % 2)
        }
        try store.save(transcript)
        let previous = ProcessInfo.processInfo.environment["TRANSCRIBE_LIBRARY_PATH"]
        setenv("TRANSCRIBE_LIBRARY_PATH", root.path, 1)
        let model = AppModel()
        if let previous { setenv("TRANSCRIBE_LIBRARY_PATH", previous, 1) } else { unsetenv("TRANSCRIBE_LIBRARY_PATH") }
        let host = NSHostingView(rootView: ContentView(model: model).frame(minWidth: 900, minHeight: 620))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let start = Date()
        host.layoutSubtreeIfNeeded()
        let initial = Date().timeIntervalSince(start)
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews($0) }
        }
        let document = try XCTUnwrap(scrollViews(host).filter { $0.bounds.width > 500 }.first)
        let scrollStart = Date()
        var slowest: TimeInterval = 0
        let passes = rapid ? 240 : 30
        for step in 0..<passes {
            let stepStart = Date()
            let maximum = max(0, (document.documentView?.frame.height ?? 0) - document.contentView.bounds.height)
            let position = rapid ? maximum * Double((step * 37) % 101) / 100 : Double((step % 15) * 160)
            document.contentView.scroll(to: NSPoint(x: 0, y: position))
            document.reflectScrolledClipView(document.contentView)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            slowest = max(slowest, Date().timeIntervalSince(stepStart))
        }
        let scrollTime = Date().timeIntervalSince(scrollStart)
        print(String(format: "DOCUMENT_LAYOUT initial=%.4fs scroll%d=%.4fs slowest=%.4fs rows=%d", initial, passes, scrollTime, slowest, transcript.segments.count))
        XCTAssertEqual(model.selected?.segments, transcript.segments)

        // Exercise the real SwiftUI/native binding and frame, not just the
        // standalone height calculator. This window is never shown onscreen.
        document.contentView.scroll(to: .zero)
        document.reflectScrolledClipView(document.contentView)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        host.layoutSubtreeIfNeeded()
        func editors(_ view: NSView) -> [RecordingNSTextView] {
            if let editor = view as? RecordingNSTextView { return [editor] }
            return view.subviews.flatMap { editors($0) }
        }
        let editor = try XCTUnwrap(editors(host).first)
        let original = editor.string
        let height = editor.frame.height
        let undo = try XCTUnwrap(editor.undoManager)
        let addition = "\n" + String(repeating: "An extra editable line åäö.\n", count: 15)
        undo.beginUndoGrouping()
        editor.insertText(addition, replacementRange: NSRange(location: (original as NSString).length, length: 0))
        undo.endUndoGrouping()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(editor.frame.height, height)
        XCTAssertTrue(model.selected?.segments.contains { $0.text == original + addition } == true)
        XCTAssertTrue(try store.loadAll().first?.segments.contains { $0.text == original + addition } == true)
        undo.undo()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(editor.string, original)
        XCTAssertEqual(model.selected?.segments, transcript.segments)
        XCTAssertEqual(try store.loadAll().first?.segments, transcript.segments)
    }
}
