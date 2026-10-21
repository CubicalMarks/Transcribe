import SwiftUI
import AppKit

// TextKit lays out the text once per width/content change, not on every scroll pass.
struct RecordingTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> RecordingNSTextView {
        let view = RecordingNSTextView()
        view.delegate = context.coordinator
        view.setContent(text)
        return view
    }

    func updateNSView(_ view: RecordingNSTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = isEnabled
        view.setAccessibilityLabel(title)
        view.setContent(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RecordingNSTextView, context: Context) -> CGSize? {
        nsView.fittingSize(proposedWidth: proposal.width)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RecordingTextField
        init(parent: RecordingTextField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? RecordingNSTextView else { return }
            view.invalidateMeasurement()
            parent.text = view.string
        }
    }
}

final class RecordingNSTextView: NSTextView {
    private var measurement: RecordingTextMeasurement?

    convenience init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isVerticallyResizable = false
        isHorizontallyResizable = false
        drawsBackground = false
        textContainerInset = .zero
        container.lineFragmentPadding = 0
        font = .systemFont(ofSize: 16)
        textColor = .textColor
        isAutomaticTextReplacementEnabled = false
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        defaultParagraphStyle = paragraph
        typingAttributes = [.font: NSFont.systemFont(ofSize: 16), .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    func setContent(_ text: String) {
        guard string != text else { return }
        string = text
        undoManager?.removeAllActions()
        invalidateMeasurement()
    }

    func invalidateMeasurement() {
        // SwiftUI owns our frame and gets a new layout proposal through the text
        // binding. Invalidating AppKit intrinsic size here also remeasures the
        // hosting window (including every visible transcript row).
        measurement?.invalidate()
    }

    func fittingSize(proposedWidth: CGFloat?) -> CGSize {
        // SwiftUI probes minimum/ideal/maximum sizes while laying out stacks and
        // sheets. Never fall back to NSTextView's intrinsic sizing for probes.
        if let width = proposedWidth, width <= 0 { return CGSize(width: 0, height: 24) }
        let width = proposedWidth.flatMap { $0.isFinite ? $0 : nil } ?? 640
        return CGSize(width: width, height: measuredHeight(width: width))
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        if measurement == nil { measurement = RecordingTextMeasurement() }
        return measurement!.height(width: width, text: textStorage ?? NSAttributedString(string: string))
    }

    var layoutMeasurementCount: Int { measurement?.layoutCount ?? 0 }
}

// Measure proposals independently: probing a narrow width must never rewrap the
// live editor or trigger its intrinsic-size/window-layout invalidation chain.
@MainActor private final class RecordingTextMeasurement {
    private let storage = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 640, height: CGFloat.greatestFiniteMagnitude))
    private var heights: [CGFloat: CGFloat] = [:]
    private var needsText = true
    private(set) var layoutCount = 0

    init() {
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
    }

    func invalidate() {
        needsText = true
        heights.removeAll(keepingCapacity: true)
    }

    func height(width: CGFloat, text: NSAttributedString) -> CGFloat {
        if let height = heights[width] { return height }
        if needsText { storage.setAttributedString(text); needsText = false }
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = max(24, ceil(max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)))
        if heights.count >= 8 { heights.removeAll(keepingCapacity: true) }
        heights[width] = height
        layoutCount += 1
        return height
    }
}
