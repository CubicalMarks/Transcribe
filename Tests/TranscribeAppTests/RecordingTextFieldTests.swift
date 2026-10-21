import XCTest
import SwiftUI
import AppKit
@testable import Transcribe

@MainActor final class RecordingTextFieldTests: XCTestCase {
    override func setUp() { super.setUp(); _ = NSApplication.shared }

    func testLongUnicodeTextWrapsAndResizesWithoutChangingContent() {
        let view = RecordingNSTextView()
        let text = String(repeating: "Svenska åäö och English 🙂 — long editable text.\n", count: 500)
        view.setContent(text)
        let wide = view.measuredHeight(width: 700)
        let narrow = view.measuredHeight(width: 240)
        XCTAssertGreaterThan(narrow, wide)
        XCTAssertEqual(view.string, text)
        for _ in 0..<1000 { XCTAssertEqual(view.measuredHeight(width: 240), narrow) }
        view.setContent("Short text")
        XCTAssertLessThan(view.measuredHeight(width: 240), narrow)
        view.setContent("Short text\n\n")
        XCTAssertGreaterThan(view.measuredHeight(width: 240), 24)
    }

    func testLayoutProbesAreFiniteAndDoNotResizeTheNativeFrame() {
        let view = RecordingNSTextView()
        view.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        let frame = view.frame
        view.setContent(String(repeating: "Short transcript section åäö.\n", count: 200))
        for width in [CGFloat(0), CGFloat.infinity, CGFloat.nan] {
            let size = view.fittingSize(proposedWidth: width)
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThanOrEqual(size.height, 24)
        }
        XCTAssertTrue(view.fittingSize(proposedWidth: nil).height.isFinite)
        let liveWidth = view.textContainer?.containerSize.width
        let wide = view.fittingSize(proposedWidth: 600)
        let narrow = view.fittingSize(proposedWidth: 250)
        let measuredPasses = view.layoutMeasurementCount
        for _ in 0..<1000 {
            XCTAssertEqual(view.fittingSize(proposedWidth: 600), wide)
            XCTAssertEqual(view.fittingSize(proposedWidth: 0), CGSize(width: 0, height: 24))
            XCTAssertEqual(view.fittingSize(proposedWidth: 250), narrow)
        }
        XCTAssertEqual(view.layoutMeasurementCount, measuredPasses)
        XCTAssertEqual(view.textContainer?.containerSize.width, liveWidth)
        XCTAssertEqual(view.frame, frame)
        XCTAssertFalse(view.isVerticallyResizable)
    }

    func testUnchangedUpdatesKeepCaretAndUndoButNewDocumentClearsUndo() throws {
        let view = RecordingNSTextView()
        view.setContent("Text with åäö")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = view
        defer { withExtendedLifetime(window) {} }
        _ = try XCTUnwrap(view.undoManager)
        let range = NSRange(location: 5, length: 4)
        view.setSelectedRange(range)
        let target = NSObject()
        view.undoManager?.registerUndo(withTarget: target) { _ in }
        view.setContent("Text with åäö")
        XCTAssertEqual(view.selectedRange(), range)
        XCTAssertTrue(view.undoManager?.canUndo == true)
        view.setContent("A different document")
        XCTAssertFalse(view.undoManager?.canUndo == true)
    }

    func testNativeTypingUsesWindowUndoAndRestoresSavedBinding() throws {
        var saved = "Original"
        let field = RecordingTextField(title: "Summary", text: Binding(get: { saved }, set: { saved = $0 }))
        let coordinator = field.makeCoordinator()
        let view = RecordingNSTextView()
        view.setContent(saved)
        view.delegate = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = view
        defer { withExtendedLifetime(window) {} }
        let undo = try XCTUnwrap(view.undoManager)
        XCTAssertTrue(undo === window.undoManager)
        undo.beginUndoGrouping()
        view.insertText("X", replacementRange: NSRange(location: 8, length: 0))
        undo.endUndoGrouping()
        XCTAssertEqual(saved, "OriginalX")
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(view.string, "Original")
        XCTAssertEqual(saved, "Original")
    }

    func testNativeChangesPublishFullTextThroughTheExistingBinding() {
        var saved = "Original"
        let field = RecordingTextField(title: "Summary", text: Binding(get: { saved }, set: { saved = $0 }))
        let coordinator = field.makeCoordinator()
        let view = RecordingNSTextView()
        view.setContent("Original")
        let oldHeight = view.measuredHeight(width: 500)
        let changed = "Edited åäö 🙂\n" + String(repeating: "Preserved paragraph.\n", count: 100)
        view.string = changed
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
        XCTAssertEqual(saved, changed)
        XCTAssertGreaterThan(view.measuredHeight(width: 500), oldHeight)
    }
}
